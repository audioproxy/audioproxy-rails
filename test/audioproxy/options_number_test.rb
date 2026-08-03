require "test_helper"
require "bigdecimal"

# The proxy hashes the normalized options string into its cache key, so a value
# rendered "12.50" instead of "12.5" is the same variant under a second cache
# key. These expectations are the proxy's rendering, spelled out.
class Audioproxy::OptionsNumberTest < ActiveSupport::TestCase
  def format(value)
    Audioproxy::Options.format_number(value)
  end

  # --- integers ------------------------------------------------------------

  test "integers render verbatim" do
    assert_equal "96", format(96)
    assert_equal "0", format(0)
    assert_equal "-16", format(-16)
    assert_equal "999999", format(999999)
  end

  # --- whole floats --------------------------------------------------------

  test "a whole float loses its fraction" do
    assert_equal "30", format(30.0)
    assert_equal "-2", format(-2.0)
    assert_equal "0", format(0.0)
  end

  test "negative zero collapses to 0" do
    assert_equal "0", format(-0.0)
  end

  # --- fractional floats ---------------------------------------------------

  test "fractional floats render minimally" do
    assert_equal "12.5", format(12.5)
    assert_equal "0.125", format(0.125)
    assert_equal "-1.5", format(-1.5)
  end

  test "trailing zeros are trimmed" do
    assert_equal "-2.5", format(-2.50)
    assert_equal "0.1", format(0.100)
  end

  test "small values never render as an exponent" do
    assert_equal "0.001", format(0.001)
    assert_equal "-0.001", format(-0.001)
    refute_includes format(0.001), "e"
  end

  test "large values never render as an exponent" do
    rendered = format(1.0e12)

    assert_equal "1000000000000", rendered
    refute_includes rendered, "e"
  end

  # --- excess precision ----------------------------------------------------

  test "more than three decimals raises rather than rounding" do
    error = assert_raises(ArgumentError) { format(0.1234) }

    assert_match(/0\.1234/, error.message)
    assert_match(/3/, error.message)
  end

  test "float arithmetic drift raises rather than emitting a second cache key" do
    assert_raises(ArgumentError) { format(0.1 + 0.2) }
  end

  test "non-finite floats raise" do
    assert_raises(ArgumentError) { format(Float::INFINITY) }
    assert_raises(ArgumentError) { format(Float::NAN) }
  end

  # --- other numerics ------------------------------------------------------

  test "rationals render through the same path" do
    assert_equal "12.5", format(Rational(25, 2))
    assert_equal "30", format(Rational(30, 1))
  end

  test "a rational that does not fit three decimals raises" do
    assert_raises(ArgumentError) { format(Rational(1, 3)) }
  end

  test "big decimals render through the same path" do
    assert_equal "12.5", format(BigDecimal("12.50"))
    assert_equal "0.125", format(BigDecimal("0.125"))
    assert_equal "30", format(BigDecimal("30"))
  end

  test "a big decimal with excess precision raises" do
    assert_raises(ArgumentError) { format(BigDecimal("0.1234")) }
  end

  # --- passthrough ---------------------------------------------------------

  test "strings pass through verbatim" do
    assert_equal "12.50", format("12.50")
    assert_equal "opus", format("opus")
  end

  test "symbols render with to_s" do
    assert_equal "opus", format(:opus)
    assert_equal "pk_fmt", format(:pk_fmt)
  end

  test "values that are neither numeric nor string-like raise" do
    assert_raises(ArgumentError) { format(nil) }
    assert_raises(ArgumentError) { format(true) }
    assert_raises(ArgumentError) { format([ 1, 2 ]) }
  end
end
