import { describe, expect, test } from "bun:test";
import { defineGate, definePresence, defineSmoke } from "./definition";

const baseline = {
  name: "baseline",
  description: "The healthy fixture passes.",
  run() {},
};

const mutation = {
  name: "mutation",
  description: "The sabotage turns the mechanism red.",
  run() {},
};

describe("evidence-class definition builders", () => {
  test("gate emits exactly one baseline and one mutation", () => {
    expect(
      defineGate({ baseline, mutation }).probes.map((probe) => probe.kind),
    ).toEqual(["baseline", "mutation"]);
  });

  test("smoke emits a baseline only", () => {
    expect(defineSmoke({ baseline }).probes.map((probe) => probe.kind)).toEqual(
      ["baseline"],
    );
  });

  test("presence emits an exists/parses baseline only", () => {
    expect(
      definePresence({ baseline }).probes.map((probe) => probe.kind),
    ).toEqual(["baseline"]);
  });
});
