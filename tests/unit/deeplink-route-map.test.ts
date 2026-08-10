import { describe, it } from 'bun:test';
import should from 'should';
import { DEEPLINK_ROUTES, appToWeb, validateRouteMap, webToApp } from '../../src/lib/deeplink/route-map';
import type { DeeplinkRoute } from '../../src/lib/deeplink/route-map';

describe('validateRouteMap', () => {
  it('should accept the shipped map', () => {
    // Arrange
    const routes = DEEPLINK_ROUTES;

    // Act
    const actual = validateRouteMap(routes);

    // Assert
    should(actual).be.empty();
  });

  it('should reject a duplicate id', () => {
    // Arrange
    const routes: DeeplinkRoute[] = [
      { id: 'a', web: '/a', app: '/app/a' },
      { id: 'a', web: '/b', app: '/app/b' },
    ];

    // Act
    const actual = validateRouteMap(routes);

    // Assert
    should(actual).matchAny((error: string) => error.includes('duplicate id'));
  });

  it('should reject an asymmetric parameter set', () => {
    // Arrange
    const routes: DeeplinkRoute[] = [{ id: 'edit', web: '/edit/:id', app: '/edit' }];

    // Act
    const actual = validateRouteMap(routes);

    // Assert
    should(actual).matchAny((error: string) => error.includes('param mismatch'));
  });

  it('should reject duplicate web and app patterns', () => {
    // Arrange
    const routes: DeeplinkRoute[] = [
      { id: 'a', web: '/same', app: '/app/same' },
      { id: 'b', web: '/same', app: '/app/same' },
    ];

    // Act
    const actual = validateRouteMap(routes);

    // Assert
    should(actual.length).equal(2);
  });
});

describe('webToApp', () => {
  it.each([
    { path: '/', expected: '/home' },
    { path: '/onboarding', expected: '/onboarding' },
    { path: '/finish', expected: '/onboarding/finish' },
    { path: '/profile', expected: '/profile' },
  ])('should map web "$path" to app "$expected"', ({ path, expected }) => {
    // Arrange

    // Act
    const actual = webToApp(path);

    // Assert
    should(actual).equal(expected);
  });

  it('should return undefined for an unmapped path', () => {
    // Arrange
    const path = '/not-a-route';

    // Act
    const actual = webToApp(path);

    // Assert
    should(actual).be.undefined();
  });

  it('should substitute parameters both ways', () => {
    // Arrange
    const routes: DeeplinkRoute[] = [{ id: 'edit', web: '/items/:id/edit', app: '/edit/:id' }];

    // Act
    const toApp = webToApp('/items/42/edit', routes);
    const toWeb = appToWeb('/edit/42', routes);

    // Assert
    should(toApp).equal('/edit/42');
    should(toWeb).equal('/items/42/edit');
  });
});

describe('appToWeb', () => {
  it('should map every shipped app route back to a web route', () => {
    // Arrange
    const routes = DEEPLINK_ROUTES;

    // Act
    const mapped = routes.map(route => appToWeb(route.app, routes));

    // Assert
    should(mapped).not.matchAny((value: string | undefined) => value === undefined);
  });

  it('should return undefined for an unmapped app route', () => {
    // Arrange
    const path = '/nope';

    // Act
    const actual = appToWeb(path);

    // Assert
    should(actual).be.undefined();
  });
});
