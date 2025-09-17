/// The Executable struct is hot potato constructed from an Intent that has been resolved.
/// It ensures that the actions are executed as intended as it can't be stored.
/// Action index is tracked to ensure each action is executed exactly once.

module account_protocol::executable;

// === Imports ===

use account_protocol::intents::Intent;

// === Structs ===

/// Hot potato ensuring the actions in the intent are executed as intended.
public struct Executable<Outcome: store> {
    // intent to return or destroy (if execution_times empty) after execution
    intent: Intent<Outcome>,
    // current action index
    action_idx: u64,
}

// === View functions ===

/// Returns the issuer of the corresponding intent
public fun intent<Outcome: store>(executable: &Executable<Outcome>): &Intent<Outcome> {
    &executable.intent
}

/// Returns the current action index
public fun action_idx<Outcome: store>(executable: &Executable<Outcome>): u64 {
    executable.action_idx
}

public fun contains_action<Outcome: store, Action: store>(
    executable: &mut Executable<Outcome>,
): bool {
    let actions_length = executable.intent().actions().length();
    let mut contains = false;
    
    actions_length.do!(|i| {
        if (executable.intent.actions().contains_with_type<u64, Action>(i)) contains = true;
    });

    contains
}

public fun next_action<Outcome: store, Action: store, IW: drop>(
    executable: &mut Executable<Outcome>,
    intent_witness: IW,
): &Action {
    executable.intent.assert_is_witness(intent_witness);

    let action_idx = executable.action_idx;
    executable.action_idx = executable.action_idx + 1;
    
    executable.intent().actions().borrow(action_idx)
}

// === Package functions ===

public(package) fun new<Outcome: store>(intent: Intent<Outcome>): Executable<Outcome> {
    Executable { intent, action_idx: 0 }
}

public(package) fun destroy<Outcome: store>(executable: Executable<Outcome>): Intent<Outcome> {
    let Executable { intent, .. } = executable;
    intent
}

//**************************************************************************************************//
// Tests                                                                                            //
//**************************************************************************************************//

#[test_only]
use std::unit_test::assert_eq;
#[test_only]
use sui::test_utils::destroy as test_destroy;
#[test_only]
use sui::clock;
#[test_only]
use account_protocol::intents;

#[test_only]
public struct TestOutcome has copy, drop, store {}
#[test_only]
public struct TestAction has store {}
#[test_only]
public struct TestIntentWitness() has drop;

#[test]
fun test_new_executable() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = intents::new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = intents::new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    let executable = new(intent);
    
    assert_eq!(action_idx(&executable), 0);
    assert_eq!(intent(&executable).key(), b"test_key".to_string());
    
    test_destroy(executable);
    test_destroy(clock);
}

#[test]
fun test_next_action() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = intents::new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let mut intent = intents::new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    intents::add_action(&mut intent, TestAction {}, TestIntentWitness());
    intents::add_action(&mut intent, TestAction {}, TestIntentWitness());
    
    let mut executable = new(intent);
    
    assert_eq!(action_idx(&executable), 0);
    
    let _action1: &TestAction = next_action(&mut executable, TestIntentWitness());
    assert_eq!(action_idx(&executable), 1);
    
    let _action2: &TestAction = next_action(&mut executable, TestIntentWitness());
    assert_eq!(action_idx(&executable), 2);
    
    test_destroy(executable);
    test_destroy(clock);
}

#[test]
fun test_contains_action() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = intents::new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let mut intent = intents::new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    intents::add_action(&mut intent, TestAction {}, TestIntentWitness());
    
    let mut executable = new(intent);
    
    assert!(contains_action<_, TestAction>(&mut executable));
    
    test_destroy(executable);
    test_destroy(clock);
}

#[test]
fun test_contains_action_empty() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = intents::new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = intents::new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    let mut executable = new(intent);
    
    assert!(!contains_action<_, TestAction>(&mut executable));
    
    test_destroy(executable);
    test_destroy(clock);
}

#[test]
fun test_destroy_executable() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = intents::new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = intents::new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    let executable = new(intent);
    let recovered_intent = destroy(executable);
    
    assert_eq!(recovered_intent.key(), b"test_key".to_string());
    assert_eq!(recovered_intent.description(), b"test_description".to_string());
    
    test_destroy(recovered_intent);
    test_destroy(clock);
}

#[test]
fun test_executable_with_multiple_actions() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = intents::new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let mut intent = intents::new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    // Add multiple actions
    intents::add_action(&mut intent, TestAction {}, TestIntentWitness());
    intents::add_action(&mut intent, TestAction {}, TestIntentWitness());
    intents::add_action(&mut intent, TestAction {}, TestIntentWitness());
    
    let mut executable = new(intent);
    
    assert_eq!(action_idx(&executable), 0);
    assert_eq!(intent(&executable).actions().length(), 3);
    
    // Execute all actions
    let _action1: &TestAction = next_action(&mut executable, TestIntentWitness());
    let _action2: &TestAction = next_action(&mut executable, TestIntentWitness());
    let _action3: &TestAction = next_action(&mut executable, TestIntentWitness());
    
    assert_eq!(action_idx(&executable), 3);
    
    test_destroy(executable);
    test_destroy(clock);
}

#[test]
fun test_intent_access() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = intents::new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = intents::new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    let executable = new(intent);
    let intent_ref = intent(&executable);
    
    assert_eq!(intent_ref.key(), b"test_key".to_string());
    assert_eq!(intent_ref.description(), b"test_description".to_string());
    assert_eq!(intent_ref.account(), @0xCAFE);
    let mut role = @account_protocol.to_string();
    role.append_utf8(b"::executable");
    role.append_utf8(b"::test_role");
    assert_eq!(intent_ref.role(), role);
    
    test_destroy(executable);
    test_destroy(clock);
}

