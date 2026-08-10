using AtomiCloud.Diene.ApiEngine.Calls;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Calls;

/// <summary>
/// The ambient binding that carries a failed exchange from the transport to the classifier.
/// </summary>
public class ApiCallScope_Binding
{
    [Fact]
    public void Nothing_is_bound_outside_a_wrapped_call()
    {
        // Load-bearing: the capture handler reads this and must be a no-op for any HttpClient a
        // consumer uses outside the engine, rather than recording into a stale scope.
        ApiCallScope.Active.Should().BeNull();
    }

    [Fact]
    public void A_scope_binds_its_own_capture_and_unbinds_on_dispose()
    {
        using (var scope = new ApiCallScope())
        {
            ApiCallScope.Active.Should().BeSameAs(scope.Capture);
        }

        ApiCallScope.Active.Should().BeNull();
    }

    [Fact]
    public void A_nested_scope_restores_the_outer_binding_rather_than_clearing_it()
    {
        using var outer = new ApiCallScope();

        using (var inner = new ApiCallScope())
        {
            ApiCallScope.Active.Should().BeSameAs(inner.Capture);
        }

        // Restored, not cleared. Clearing would leave a call made from inside another wrapped call
        // unable to classify its own failure — and the outer call would look like it never had one.
        ApiCallScope.Active.Should().BeSameAs(outer.Capture);
    }

    [Fact]
    public void Disposing_twice_does_not_unbind_a_second_time()
    {
        var outer = new ApiCallScope();
        var inner = new ApiCallScope();

        inner.Dispose();
        inner.Dispose();

        ApiCallScope.Active.Should().BeSameAs(outer.Capture, "the second dispose must not pop again");
        outer.Dispose();
    }

    [Fact]
    public void A_capture_counts_attempts_and_keeps_the_last_failure()
    {
        var capture = new ApiCallCapture();

        capture.Failure.Should().BeNull();
        capture.Attempts.Should().Be(0);

        capture.RecordAttempt();
        capture.RecordFailure(new ApiFailure(500, "application/json", "first"));
        capture.RecordAttempt();
        capture.RecordFailure(new ApiFailure(503, "application/json", "second"));

        // Last write wins: a retried request produces two exchanges, and it is the final one that
        // describes the outcome the caller actually received.
        capture.Attempts.Should().Be(2);
        capture.Failure!.Body.Should().Be("second");
    }
}
