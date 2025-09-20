#[test_only]
module account_protocol::intents_tests;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    test_utils::destroy,
    test_scenario as ts,
    clock,
};
use account_protocol::{
    intents,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has drop;
public struct WrongIntent() has drop;
public struct DummyAction has store {}

// === Helpers ===

fun full_role(): String {
    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::intents_tests::Degen");
    full_role
}

// === Tests ===

#[test]
fun test_params() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());
    
    let params = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    );

    assert!(params.key() == b"one".to_string());
    assert!(params.description() == b"".to_string());
    assert!(params.creation_time() == clock.timestamp_ms());
    assert!(params.execution_times() == vector[0]);
    assert!(params.expiration_time() == 1);

    destroy(params);
    destroy(clock);
    scenario.end();
}

#[test]
fun test_params_rand() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());
    
    let (params, key) = intents::new_params_with_rand_key(
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    );

    assert!(params.key() == key);
    assert!(params.description() == b"".to_string());
    assert!(params.creation_time() == clock.timestamp_ms());
    assert!(params.execution_times() == vector[0]);
    assert!(params.expiration_time() == 1);

    destroy(params);
    destroy(clock);
    scenario.end();
}

#[test]
fun test_getters() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    // create intents
    let mut intents = intents::empty(scenario.ctx());
    let intent1 = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intents.add_intent(intent1);

    let intent2 = intents::new_params(
        b"two".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intents.add_intent(intent2);

    // check intents getters
    assert!(intents.length() == 2);
    assert!(intents.contains(b"one".to_string()));
    assert!(intents.contains(b"two".to_string()));

    // check intent getters
    let intent1 = intents.get(b"one".to_string());
    assert!(intent1.type_() == type_name::with_defining_ids<DummyIntent>());
    assert!(intent1.key() == b"one".to_string());
    assert!(intent1.description() == b"".to_string());
    assert!(intent1.account() == @0xACC);
    assert!(intent1.creator() == OWNER);
    assert!(intent1.creation_time() == 1);
    assert!(intent1.execution_times() == vector[0]);
    assert!(intent1.expiration_time() == 1);
    assert!(intent1.actions().length() == 0);
    assert!(intent1.role() == full_role());
    assert!(intent1.outcome() == true);

    intent1.assert_is_account(@0xACC);
    intent1.assert_is_witness(DummyIntent());

    let intent_mut1 = intents.get_mut(b"one".to_string());
    let outcome = intent_mut1.outcome_mut();
    assert!(outcome == true);

    // check expired getters
    let expired = intents.destroy_intent<bool>(b"one".to_string());
    assert!(expired.account() == @0xACC);
    assert!(expired.start_index() == 0);
    assert!(expired.actions().length() == 0);

    destroy(expired);
    destroy(intents);
    destroy(clock);
    scenario.end();
}

#[test]
fun test_add_remove_action() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let mut intents = intents::empty(scenario.ctx());
    let mut intent = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intent.add_action(DummyAction {}, DummyIntent());
    assert!(intent.actions().length() == 1);
    intents.add_intent(intent);

    let mut expired = intents.destroy_intent<bool>(b"one".to_string());
    let DummyAction {} = expired.remove_action();

    destroy(intents);
    destroy(expired);
    destroy(clock);
    scenario.end();
}

#[test]
fun test_pop_front_execution_time() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);
    
    let mut intent = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intent.add_action(DummyAction {}, DummyIntent());
    
    let time = intent.pop_front_execution_time();
    assert!(time == 0);
    assert!(intent.execution_times().is_empty());

    destroy(clock);
    destroy(intent);
    scenario.end();
}

#[test]
fun test_add_destroy_intent() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intents = intents::empty(scenario.ctx());
    let intent = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intents.add_intent(intent);
    // remove intent
    let _time = intents.get_mut<bool>(b"one".to_string()).pop_front_execution_time();
    let expired = intents.destroy_intent<bool>(b"one".to_string());
    assert!(expired.account() == @0xACC);
    assert!(expired.start_index() == 0);
    assert!(expired.actions().length() == 0);
    expired.destroy_empty();

    destroy(clock);
    destroy(intents);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EIntentNotFound)]
fun test_error_get_intent() {
    let mut scenario = ts::begin(OWNER);

    let intents = intents::empty(scenario.ctx());
    let _ = intents.get<bool>(b"one".to_string());

    destroy(intents);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EIntentNotFound)]
fun test_error_get_mut_intent() {
    let mut scenario = ts::begin(OWNER);

    let mut intents = intents::empty(scenario.ctx());
    let _ = intents.get_mut<bool>(b"one".to_string());

    destroy(intents);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_not_account() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    // create intents
    let intent = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );

    intent.assert_is_account(@0x0);

    destroy(intent);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_wrong_witness() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    // create intents
    let intent = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );

    intent.assert_is_witness(WrongIntent());

    destroy(clock);
    destroy(intent);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EActionsNotEmpty)]
fun test_error_delete_intent_actions_not_empty() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let mut intents = intents::empty(scenario.ctx());
    let mut intent = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intent.add_action(DummyAction {}, DummyIntent());
    intents.add_intent(intent);
    // remove intent
    let expired = intents.destroy_intent<bool>(b"one".to_string());
    expired.destroy_empty();

    destroy(intents);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EKeyAlreadyExists)]
fun test_error_add_intent_key_already_exists() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intents = intents::empty(scenario.ctx());
    let intent1 = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intents.add_intent(intent1);
    let intent2 = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[0],
        1,
        &clock,
        scenario.ctx()
    ).new_intent(
        true,
        b"Degen".to_string(),
        @0xACC,
        DummyIntent(),
        scenario.ctx(),
    );
    intents.add_intent(intent2);

    destroy(intents);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::ENoExecutionTime)]
fun test_error_no_execution_time() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[],
        1,
        &clock,
        scenario.ctx()
    );

    destroy(clock);
    destroy(params);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EExecutionTimesNotAscending)]
fun test_error_execution_times_not_ascending() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(),
        b"".to_string(),
        vector[1, 0],
        1,
        &clock,
        scenario.ctx()
    );

    destroy(clock);
    destroy(params);
    scenario.end();
}