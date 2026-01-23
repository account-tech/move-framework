#[test_only]
module account_protocol::executable_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{
    test_scenario as ts,
    clock,
};
use account_protocol::{
    executable,
    intents,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has drop;
public struct WrongIntent() has drop;

public struct Outcome has copy, drop, store {}
public struct Action has store {}

// === Tests ===

#[test]
fun test_executable_flow() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[1],
        1,
        &clock,
        scenario.ctx()
    );

    let mut intent = intents::new_intent(
        params,
        Outcome {},
        b"".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intent.add_action(Action {}, DummyIntent());

    let mut executable = executable::new(intent);
    // verify initial state (pending action)
    assert!(executable.intent().key() == b"one".to_string());
    assert!(executable.action_idx() == 0);
    // first step: execute action
    let _: &Action = executable.next_action(DummyIntent());
    assert!(executable.action_idx() == 1);
    // second step: destroy executable
    let intent = executable.destroy();

    destroy(intent);
    destroy(clock);
    ts::end(scenario);
}