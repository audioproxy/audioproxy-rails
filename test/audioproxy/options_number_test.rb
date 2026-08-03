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

  # A double's spacing exceeds 0.001 past 2**42 or so, and printf("%.3f")
  # re-reads the underlying binary value rather than the decimal the caller
  # wrote: it renders 12345678901234.56 as "12345678901234.561". Rendering has
  # to come from the value's own shortest decimal spelling.
  test "values larger than a double's decimal spacing render as written" do
    assert_equal "12345678901234.56", format(12345678901234.56)
    assert_equal "999999999999999.9", format(999999999999999.9)
  end

  test "a rendered value never ends in a bare decimal point" do
    [ 12345678901234.56, 999999999999999.9, 1.0e12, BigDecimal("12345678901234567.5") ].each do |value|
      refute_match(/\.\z/, format(value), "#{value.inspect} rendered a dangling point")
    end
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

  # The point of accepting a BigDecimal is carrying more digits than a double
  # holds, so rendering must not route back through one.
  test "big decimals keep digits a double would lose" do
    assert_equal "12345678901234567.5", format(BigDecimal("12345678901234567.5"))
    assert_equal "123456789012345678901234567890.5",
      format(BigDecimal("123456789012345678901234567890.5"))
  end

  test "non-finite big decimals raise" do
    assert_raises(ArgumentError) { format(BigDecimal("NaN")) }
    assert_raises(ArgumentError) { format(BigDecimal("Infinity")) }
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

  # Complex is Numeric, but Complex#round does not exist: without an explicit
  # rejection this escapes as NoMethodError rather than the ArgumentError the
  # module promises for a value it cannot render.
  test "complex numbers raise ArgumentError, not NoMethodError" do
    assert_raises(ArgumentError) { format(Complex(1.0)) }
    assert_raises(ArgumentError) { format(Complex(1, 2)) }
  end
end
