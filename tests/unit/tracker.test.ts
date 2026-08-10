import { describe, it } from 'bun:test';
import should from 'should';
import { createTracker, type TrackEvent } from '../../src/lib/tracker';

describe('createTracker', () => {
  it('should deliver events to subscribers', () => {
    // Arrange
    const tracker = createTracker();
    const received: TrackEvent[] = [];
    tracker.subscribe(event => received.push(event));

    // Act
    tracker.track({ name: 'click', attributes: { target: 'cta' } });

    // Assert
    should(received.length).equal(1);
    should(received[0]?.name).equal('click');
  });

  it('should stop delivering after unsubscribe', () => {
    // Arrange
    const tracker = createTracker();
    const received: TrackEvent[] = [];
    const unsubscribe = tracker.subscribe(event => received.push(event));

    // Act
    unsubscribe();
    tracker.track({ name: 'ignored' });

    // Assert
    should(received).be.empty();
  });

  it('should fan out to multiple subscribers', () => {
    // Arrange
    const tracker = createTracker();
    let first = 0;
    let second = 0;
    tracker.subscribe(() => {
      first += 1;
    });
    tracker.subscribe(() => {
      second += 1;
    });

    // Act
    tracker.track({ name: 'page_view' });

    // Assert
    should(first).equal(1);
    should(second).equal(1);
  });
});
