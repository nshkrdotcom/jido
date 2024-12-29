defmodule Jido.Actions.CalculatorTest do
  use ExUnit.Case, async: true
  alias Jido.Actions.Calculator

  # Test for Add action
  describe "Add" do
    test "adds two numbers correctly" do
      assert {:ok, %{result: 5}} = Calculator.Add.run(%{value: 2, amount: 3}, %{})
      assert {:ok, %{result: -1}} = Calculator.Add.run(%{value: -3, amount: 2}, %{})
      assert {:ok, %{result: 0}} = Calculator.Add.run(%{value: 0, amount: 0}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: 5.5}} = Calculator.Add.run(%{value: 2.5, amount: 3.0}, %{})
    end
  end

  # Test for Subtract action
  describe "Subtract" do
    test "subtracts two numbers correctly" do
      assert {:ok, %{result: -1}} = Calculator.Subtract.run(%{value: 2, amount: 3}, %{})
      assert {:ok, %{result: -5}} = Calculator.Subtract.run(%{value: -3, amount: 2}, %{})
      assert {:ok, %{result: 0}} = Calculator.Subtract.run(%{value: 0, amount: 0}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: -0.5}} = Calculator.Subtract.run(%{value: 2.5, amount: 3.0}, %{})
    end
  end

  # Test for Multiply action
  describe "Multiply" do
    test "multiplies two numbers correctly" do
      assert {:ok, %{result: 6}} = Calculator.Multiply.run(%{value: 2, amount: 3}, %{})
      assert {:ok, %{result: -6}} = Calculator.Multiply.run(%{value: -3, amount: 2}, %{})
      assert {:ok, %{result: 0}} = Calculator.Multiply.run(%{value: 0, amount: 5}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: 7.5}} = Calculator.Multiply.run(%{value: 2.5, amount: 3.0}, %{})
    end
  end

  # Test for Divide action
  describe "Divide" do
    test "divides two numbers correctly" do
      assert {:ok, %{result: 2.0}} = Calculator.Divide.run(%{value: 6, amount: 3}, %{})
      assert {:ok, %{result: -1.5}} = Calculator.Divide.run(%{value: -3, amount: 2}, %{})
    end

    test "returns error when dividing by zero" do
      assert {:error, "Cannot divide by zero"} =
               Calculator.Divide.run(%{value: 5, amount: 0}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: 0.8333333333333334}} =
               Calculator.Divide.run(%{value: 2.5, amount: 3.0}, %{})
    end
  end

  # Test for Square action
  describe "Square" do
    test "squares a number correctly" do
      assert {:ok, %{result: 4}} = Calculator.Square.run(%{value: 2}, %{})
      assert {:ok, %{result: 9}} = Calculator.Square.run(%{value: -3}, %{})
      assert {:ok, %{result: 0}} = Calculator.Square.run(%{value: 0}, %{})
    end

    test "works with floating point numbers" do
      assert {:ok, %{result: 6.25}} = Calculator.Square.run(%{value: 2.5}, %{})
    end
  end
end
