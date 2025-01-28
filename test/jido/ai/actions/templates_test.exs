defmodule Jido.AI.Actions.TemplatesTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Templates

  describe "template creation" do
    test "creates template with required fields" do
      {:ok, template} =
        Templates.create_template(
          "user_profile",
          "Creates a user profile",
          "Create a profile for {name} who is {age} years old",
          [:name, :age]
        )

      assert template.name == "user_profile"
      assert template.description == "Creates a user profile"
      assert template.template == "Create a profile for {name} who is {age} years old"
      assert template.variables == [:name, :age]
      assert template.examples == []
      assert template.parent == nil

      assert template.options == %{
               chain_of_thought: false,
               few_shot: false,
               max_examples: 3
             }
    end

    test "creates template with examples and options" do
      examples = [
        %{name: "John", age: 30},
        %{name: "Jane", age: 25}
      ]

      {:ok, template} =
        Templates.create_template(
          "user_profile",
          "Creates a user profile",
          "Create a profile for {name} who is {age} years old",
          [:name, :age],
          examples: examples,
          options: %{chain_of_thought: true, few_shot: true}
        )

      assert template.examples == examples
      assert template.options.chain_of_thought == true
      assert template.options.few_shot == true
    end

    test "validates template options" do
      result =
        Templates.create_template(
          "user_profile",
          "Creates a user profile",
          "Create a profile for {name} who is {age} years old",
          [:name, :age],
          options: %{max_examples: "invalid"}
        )

      assert {:error, message} = result
      assert message =~ "invalid value for :max_examples option"
    end
  end

  describe "template rendering" do
    test "renders template with valid variables" do
      {:ok, template} =
        Templates.create_template(
          "user_profile",
          "Creates a user profile",
          "Create a profile for {name} who is {age} years old",
          [:name, :age]
        )

      result = Templates.render_template(template, %{name: "John", age: 30})
      assert {:ok, rendered} = result
      assert rendered == "Create a profile for John who is 30 years old"
    end

    test "handles missing variables" do
      {:ok, template} =
        Templates.create_template(
          "user_profile",
          "Creates a user profile",
          "Create a profile for {name} who is {age} years old",
          [:name, :age]
        )

      result = Templates.render_template(template, %{name: "John"})
      assert {:error, message} = result
      assert message =~ "Missing required variables"
      assert message =~ ":age"
    end

    test "renders template with chain of thought" do
      {:ok, template} =
        Templates.create_template(
          "math_problem",
          "Solves a math problem",
          "Solve: {problem}",
          [:problem],
          options: %{chain_of_thought: true}
        )

      {:ok, rendered} = Templates.render_template(template, %{problem: "2 + 2"})
      assert rendered =~ "Let's solve this step by step"
      assert rendered =~ "1. First"
      assert rendered =~ "2. Then"
      assert rendered =~ "3. Finally"
    end

    test "renders template with examples" do
      examples = [
        %{name: "John", age: 30},
        %{name: "Jane", age: 25}
      ]

      {:ok, template} =
        Templates.create_template(
          "user_profile",
          "Creates a user profile",
          "Create a profile for {name} who is {age} years old",
          [:name, :age],
          examples: examples,
          options: %{few_shot: true}
        )

      {:ok, rendered} = Templates.render_template(template, %{name: "Alice", age: 35})
      assert rendered =~ "Here are some examples:"
      assert rendered =~ "Example:\nCreate a profile for John who is 30 years old"
      assert rendered =~ "Example:\nCreate a profile for Jane who is 25 years old"
      assert rendered =~ "Create a profile for Alice who is 35 years old"
    end
  end

  describe "template composition" do
    test "composes templates with inheritance" do
      {:ok, parent} =
        Templates.create_template(
          "base_profile",
          "Base profile template",
          "Basic info:\n{name}, {age} years old",
          [:name, :age]
        )

      {:ok, child} =
        Templates.compose(
          parent,
          "detailed_profile",
          "Detailed profile template",
          "Additional info:\nEmail: {email}",
          [:name, :age, :email]
        )

      {:ok, rendered} =
        Templates.render_template(child, %{
          name: "John",
          age: 30,
          email: "john@example.com"
        })

      assert rendered =~ "Basic info:"
      assert rendered =~ "John, 30 years old"
      assert rendered =~ "Additional info:"
      assert rendered =~ "Email: john@example.com"
    end

    test "validates composed template" do
      {:ok, parent} =
        Templates.create_template(
          "base_profile",
          "Base profile template",
          "Basic info:\n{name}, {age} years old",
          [:name, :age]
        )

      result =
        Templates.compose(
          parent,
          123,
          "Detailed profile template",
          "Additional info",
          [:email]
        )

      assert {:error, message} = result
      assert message =~ "Name must be a string"
    end
  end

  describe "template options" do
    test "updates template options" do
      {:ok, template} =
        Templates.create_template(
          "user_profile",
          "Creates a user profile",
          "Create a profile for {name} who is {age} years old",
          [:name, :age]
        )

      {:ok, updated} =
        Templates.update_options(template, %{
          chain_of_thought: true,
          max_examples: 5
        })

      assert updated.options.chain_of_thought == true
      assert updated.options.max_examples == 5
      assert updated.options.few_shot == false
    end

    test "validates option updates" do
      {:ok, template} =
        Templates.create_template(
          "user_profile",
          "Creates a user profile",
          "Create a profile for {name} who is {age} years old",
          [:name, :age]
        )

      result = Templates.update_options(template, %{max_examples: "invalid"})
      assert {:error, message} = result
      assert message =~ "invalid value for :max_examples option"
    end
  end
end
