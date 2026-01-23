/// This is the core module managing Intents.
/// It provides the interface to create and execute intents which is used in the `account` module.
/// The `locked` field tracks the owned objects used in an intent, to prevent state changes.
/// e.g. withdraw coinA (value=10sui), coinA must not be split before intent is executed.

module account_protocol::intents;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use sui::{
    bag::{Self, Bag},
    dynamic_field,
    clock::Clock,
};

// === Aliases ===

use fun dynamic_field::add as UID.df_add;
use fun dynamic_field::borrow as UID.df_borrow;
use fun dynamic_field::remove as UID.df_remove;

// === Errors ===

const EIntentNotFound: u64 = 0;
const ENoExecutionTime: u64 = 1;
const EExecutionTimesNotAscending: u64 = 2;
const EActionsNotEmpty: u64 = 3;
const EKeyAlreadyExists: u64 = 4;
const EWrongAccount: u64 = 5;
const EWrongWitness: u64 = 6;
const ESingleExecution: u64 = 7;

// === Structs ===

/// Parent struct protecting the intents
public struct Intents has store {
    // map of intents: key -> Intent<Outcome>
    inner: Bag,
}

/// Child struct, intent owning a sequence of actions requested to be executed
/// Outcome is a custom struct depending on the config
public struct Intent<Outcome> has store {
    // type of the intent, checked against the witness to ensure correct execution
    type_: TypeName,
    // name of the intent, serves as a key, should be unique
    key: String,
    // what this intent aims to do, for informational purpose
    description: String,
    // address of the account that created the intent
    account: address,
    // address of the user that created the intent
    creator: address,
    // timestamp of the intent creation
    creation_time: u64,
    // proposer can add a timestamp_ms before which the intent can't be executed
    // can be used to schedule actions via a backend
    // recurring intents can be executed at these times
    execution_times: vector<u64>,
    // the intent can be deleted from this timestamp
    expiration_time: u64,
    // role for the intent 
    role: String,
    // heterogenous array of actions to be executed in order
    actions: Bag,
    // Generic struct storing vote related data, depends on the config
    outcome: Outcome
}

/// Hot potato wrapping actions from an intent that expired or has been executed
public struct Expired {
    // address of the account that created the intent
    account: address,
    // index of the first action in the bag
    start_index: u64,
    // actions that expired
    actions: Bag
}

/// Params of an intent to reduce boilerplate.
public struct Params has key, store {
    id: UID,
}
/// Fields are a df so it intents can be improved in the future
public struct ParamsFieldsV1 has copy, drop, store {
    key: String,
    description: String,
    creation_time: u64,
    execution_times: vector<u64>,
    expiration_time: u64,
}

// === Public functions ===

public fun new_params(
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Params {
    assert!(!execution_times.is_empty(), ENoExecutionTime);
    let mut i = 0;
    while (i < vector::length(&execution_times) - 1) {
        assert!(execution_times[i] <= execution_times[i + 1], EExecutionTimesNotAscending);
        i = i + 1;
    };
    
    let fields = ParamsFieldsV1 { 
        key, 
        description, 
        creation_time: clock.timestamp_ms(), 
        execution_times, 
        expiration_time 
    };
    let mut id = object::new(ctx);
    id.df_add(true, fields);

    Params { id }
}

public fun new_params_with_rand_key(
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Params, String) {
    let key = ctx.fresh_object_address().to_string();
    let params = new_params(key, description, execution_times, expiration_time, clock, ctx);

    (params, key)
}

public fun add_action<Outcome, Action: store, IW: drop>(
    intent: &mut Intent<Outcome>,
    action: Action,
    intent_witness: IW,
) {
    intent.assert_is_witness(intent_witness);

    let idx = intent.actions().length();
    intent.actions_mut().add(idx, action);
}

public fun remove_action<Action: store>(
    expired: &mut Expired, 
): Action {
    let idx = expired.start_index;
    expired.start_index = idx + 1;

    expired.actions.remove(idx)
}

public use fun destroy_empty_expired as Expired.destroy_empty;
public fun destroy_empty_expired(expired: Expired) {
    let Expired { actions, .. } = expired;
    assert!(actions.is_empty(), EActionsNotEmpty);
    actions.destroy_empty();
}

// === View functions ===

public use fun params_key as Params.key;
public fun params_key(params: &Params): String {
    params.id.df_borrow<_, ParamsFieldsV1>(true).key
}

public use fun params_description as Params.description;
public fun params_description(params: &Params): String {
    params.id.df_borrow<_, ParamsFieldsV1>(true).description
}

public use fun params_creation_time as Params.creation_time;
public fun params_creation_time(params: &Params): u64 {
    params.id.df_borrow<_, ParamsFieldsV1>(true).creation_time
}

public use fun params_execution_times as Params.execution_times;
public fun params_execution_times(params: &Params): vector<u64> {
    params.id.df_borrow<_, ParamsFieldsV1>(true).execution_times
}

public use fun params_expiration_time as Params.expiration_time;
public fun params_expiration_time(params: &Params): u64 {
    params.id.df_borrow<_, ParamsFieldsV1>(true).expiration_time
}

public fun length(intents: &Intents): u64 {
    intents.inner.length()
}

public fun contains(intents: &Intents, key: String): bool {
    intents.inner.contains(key)
}

public fun get<Outcome: store>(intents: &Intents, key: String): &Intent<Outcome> {
    assert!(intents.inner.contains(key), EIntentNotFound);
    intents.inner.borrow(key)
}

public fun get_mut<Outcome: store>(intents: &mut Intents, key: String): &mut Intent<Outcome> {
    assert!(intents.inner.contains(key), EIntentNotFound);
    intents.inner.borrow_mut(key)
}

public fun type_<Outcome>(intent: &Intent<Outcome>): TypeName {
    intent.type_
}

public fun key<Outcome>(intent: &Intent<Outcome>): String {
    intent.key
}

public fun description<Outcome>(intent: &Intent<Outcome>): String {
    intent.description
}

public fun account<Outcome>(intent: &Intent<Outcome>): address {
    intent.account
}

public fun creator<Outcome>(intent: &Intent<Outcome>): address {
    intent.creator
}

public fun creation_time<Outcome>(intent: &Intent<Outcome>): u64 {
    intent.creation_time
}

public fun execution_times<Outcome>(intent: &Intent<Outcome>): vector<u64> {
    intent.execution_times
}

public fun expiration_time<Outcome>(intent: &Intent<Outcome>): u64 {
    intent.expiration_time
}

public fun role<Outcome>(intent: &Intent<Outcome>): String {
    intent.role
}

public fun actions<Outcome>(intent: &Intent<Outcome>): &Bag {
    &intent.actions
}

public fun actions_mut<Outcome>(intent: &mut Intent<Outcome>): &mut Bag {
    &mut intent.actions
}

public fun outcome<Outcome>(intent: &Intent<Outcome>): &Outcome {
    &intent.outcome
}

public fun outcome_mut<Outcome>(intent: &mut Intent<Outcome>): &mut Outcome {
    &mut intent.outcome
}

public use fun expired_account as Expired.account;
public fun expired_account(expired: &Expired): address {
    expired.account
}

public use fun expired_start_index as Expired.start_index;
public fun expired_start_index(expired: &Expired): u64 {
    expired.start_index
}

public use fun expired_actions as Expired.actions;
public fun expired_actions(expired: &Expired): &Bag {
    &expired.actions
}

public fun assert_is_account<Outcome>(
    intent: &Intent<Outcome>,
    account_addr: address,
) {
    assert!(intent.account == account_addr, EWrongAccount);
}

public fun assert_is_witness<Outcome, IW: drop>(
    intent: &Intent<Outcome>,
    _: IW,
) {
    assert!(intent.type_ == type_name::with_defining_ids<IW>(), EWrongWitness);
}

public use fun assert_expired_is_account as Expired.assert_is_account;
public fun assert_expired_is_account(expired: &Expired, account_addr: address) {
    assert!(expired.account == account_addr, EWrongAccount);
}

public fun assert_single_execution(params: &Params) {
    assert!(
        params.id.df_borrow<_, ParamsFieldsV1>(true).execution_times.length() == 1, 
        ESingleExecution
    );
}

// === Package functions ===

/// The following functions are only used in the `account` module

public(package) fun empty(ctx: &mut TxContext): Intents {
    Intents { inner: bag::new(ctx) }
}

public(package) fun new_intent<Outcome, IW: drop>(
    params: Params,
    outcome: Outcome,
    managed_name: String,
    account_addr: address,
    _intent_witness: IW,
    ctx: &mut TxContext
): Intent<Outcome> {
    let Params { mut id } = params;
    
    let ParamsFieldsV1 { 
        key, 
        description, 
        creation_time, 
        execution_times, 
        expiration_time 
    } = id.df_remove(true);
    id.delete();

    Intent<Outcome> { 
        type_: type_name::with_defining_ids<IW>(),
        key,
        description,
        account: account_addr,
        creator: ctx.sender(),
        creation_time,
        execution_times,
        expiration_time,
        role: new_role<IW>(managed_name),
        actions: bag::new(ctx),
        outcome
    }
}

public(package) fun add_intent<Outcome: store>(
    intents: &mut Intents,
    intent: Intent<Outcome>,
) {
    assert!(!intents.contains(intent.key), EKeyAlreadyExists);
    intents.inner.add(intent.key, intent);
}

public(package) fun remove_intent<Outcome: store>(
    intents: &mut Intents,
    key: String,
): Intent<Outcome> {
    assert!(intents.contains(key), EIntentNotFound);
    intents.inner.remove(key)
}

public(package) fun pop_front_execution_time<Outcome>(
    intent: &mut Intent<Outcome>,
): u64 {
    intent.execution_times.remove(0)
}

/// Removes an intent being executed if the execution_time is reached
/// Outcome must be validated in AccountMultisig to be destroyed
public(package) fun destroy_intent<Outcome: store + drop>(
    intents: &mut Intents,
    key: String,
): Expired {
    let Intent<Outcome> { account, actions, .. } = intents.inner.remove(key);
    
    Expired { account, start_index: 0, actions }
}

// === Private functions ===

fun new_role<IW: drop>(managed_name: String): String {
    let intent_type = type_name::with_defining_ids<IW>();
    let mut role = intent_type.address_string().to_string();
    role.append_utf8(b"::");
    role.append(intent_type.module_string().to_string());

    if (!managed_name.is_empty()) {
        role.append_utf8(b"::");
        role.append(managed_name);
    };

    role
}

//**************************************************************************************************//
// Tests                                                                                            //
//**************************************************************************************************//

#[test_only]
use std::unit_test::{assert_eq, destroy};
#[test_only]
use sui::clock;

#[test_only]
public struct TestOutcome has copy, drop, store {}
#[test_only]
public struct TestAction has store {}
#[test_only]
public struct TestIntentWitness() has drop;
#[test_only]
public struct WrongWitness() has drop;

#[test]
fun test_new_params() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    assert_eq!(params.key(), b"test_key".to_string());
    assert_eq!(params.description(), b"test_description".to_string());
    assert_eq!(params.execution_times(), vector[1000]);
    assert_eq!(params.expiration_time(), 2000);
    assert_eq!(params.creation_time(), 0);
    
    destroy(params);
    destroy(clock);
}

#[test]
fun test_new_params_with_rand_key() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let (params, key) = new_params_with_rand_key(
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    assert_eq!(params.key(), key);
    assert_eq!(params.description(), b"test_description".to_string());
    assert_eq!(params.execution_times(), vector[1000]);
    assert_eq!(params.expiration_time(), 2000);
    
    destroy(params);
    destroy(clock);
}

#[test, expected_failure(abort_code = ENoExecutionTime)]
fun test_new_params_empty_execution_times() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[],
        2000,
        &clock,
        ctx
    );
    destroy(params);
    destroy(clock);
}

#[test, expected_failure(abort_code = EExecutionTimesNotAscending)]
fun test_new_params_not_ascending_execution_times() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[2000, 1000],
        3000,
        &clock,
        ctx
    );
    destroy(params);
    destroy(clock);
}

#[test]
fun test_new_intent() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    assert_eq!(intent.key(), b"test_key".to_string());
    assert_eq!(intent.description(), b"test_description".to_string());
    assert_eq!(intent.account(), @0xCAFE);
    assert_eq!(intent.creation_time(), clock.timestamp_ms());
    assert_eq!(intent.execution_times(), vector[1000]);
    assert_eq!(intent.expiration_time(), 2000);
    assert_eq!(intent.actions().length(), 0);
    
    destroy(intent);
    destroy(clock);
}

#[test]
fun test_add_action() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let mut intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    add_action(&mut intent, TestAction {}, TestIntentWitness());
    assert_eq!(intent.actions().length(), 1);
    
    add_action(&mut intent, TestAction {}, TestIntentWitness());
    assert_eq!(intent.actions().length(), 2);
    
    destroy(intent);
    destroy(clock);
}

#[test]
fun test_remove_action() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    let mut intents = empty(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let mut intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    add_action(&mut intent, TestAction {}, TestIntentWitness());
    add_action(&mut intent, TestAction {}, TestIntentWitness());
    add_intent(&mut intents, intent);
    
    let mut expired = intents.destroy_intent<TestOutcome>(b"test_key".to_string());
    
    let action1: TestAction = remove_action(&mut expired);
    let action2: TestAction = remove_action(&mut expired);
    
    assert_eq!(expired.start_index, 2);
    assert_eq!(expired.actions().length(), 0);
    
    expired.destroy_empty();
    destroy(intents);
    destroy(clock);
    destroy(action1);
    destroy(action2);
}

#[test]
fun test_empty_intents() {
    let ctx = &mut tx_context::dummy();
    let intents = empty(ctx);
    
    assert_eq!(length(&intents), 0);
    assert!(!contains(&intents, b"test_key".to_string()));
    
    destroy(intents);
}

#[test]
fun test_add_and_remove_intent() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    let mut intents = empty(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    add_intent(&mut intents, intent);
    assert_eq!(length(&intents), 1);
    assert!(contains(&intents, b"test_key".to_string()));
    
    let removed_intent = remove_intent<TestOutcome>(&mut intents, b"test_key".to_string());
    assert_eq!(length(&intents), 0);
    assert!(!contains(&intents, b"test_key".to_string()));
    
    destroy(removed_intent);
    destroy(intents);
    destroy(clock);
}

#[test, expected_failure(abort_code = EKeyAlreadyExists)]
fun test_add_duplicate_intent() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    let mut intents = empty(ctx);
    
    let params1 = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let params2 = new_params(
        b"test_key".to_string(),
        b"test_description2".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent1 = new_intent(
        params1,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    let intent2 = new_intent(
        params2,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    add_intent(&mut intents, intent1);
    add_intent(&mut intents, intent2);
    
    destroy(intents);
    destroy(clock);
}

#[test, expected_failure(abort_code = EIntentNotFound)]
fun test_remove_nonexistent_intent() {
    let ctx = &mut tx_context::dummy();
    let mut intents = empty(ctx);
    
    let removed_intent = remove_intent<TestOutcome>(&mut intents, b"nonexistent_key".to_string());
    
    destroy(removed_intent);
    destroy(intents);
}

#[test]
fun test_pop_front_execution_time() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000, 2000, 3000],
        4000,
        &clock,
        ctx
    );
    
    let mut intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    assert_eq!(intent.execution_times(), vector[1000, 2000, 3000]);
    
    let time1 = pop_front_execution_time(&mut intent);
    assert_eq!(time1, 1000);
    assert_eq!(intent.execution_times(), vector[2000, 3000]);
    
    let time2 = pop_front_execution_time(&mut intent);
    assert_eq!(time2, 2000);
    assert_eq!(intent.execution_times(), vector[3000]);
    
    destroy(intent);
    destroy(clock);
}

#[test]
fun test_assert_is_account() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    // Should not abort
    assert_is_account(&intent, @0xCAFE);
    
    destroy(intent);
    destroy(clock);
}

#[test, expected_failure(abort_code = EWrongAccount)]
fun test_assert_is_account_wrong() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    assert_is_account(&intent, @0xBAD);
    
    destroy(intent);
    destroy(clock);
}

#[test]
fun test_assert_is_witness() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    // Should not abort
    assert_is_witness(&intent, TestIntentWitness());
    
    destroy(intent);
    destroy(clock);
}

#[test, expected_failure(abort_code = EWrongWitness)]
fun test_assert_is_witness_wrong() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    let intent = new_intent(
        params,
        TestOutcome {},
        b"test_role".to_string(),
        @0xCAFE,
        TestIntentWitness(),
        ctx
    );
    
    assert_is_witness(&intent, WrongWitness());
    
    destroy(intent);
    destroy(clock);
}

#[test]
fun test_assert_single_execution() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000],
        2000,
        &clock,
        ctx
    );
    
    // Should not abort
    assert_single_execution(&params);
    
    destroy(params);
    destroy(clock);
}

#[test, expected_failure(abort_code = ESingleExecution)]
fun test_assert_single_execution_multiple() {
    let ctx = &mut tx_context::dummy();
    let clock = clock::create_for_testing(ctx);
    
    let params = new_params(
        b"test_key".to_string(),
        b"test_description".to_string(),
        vector[1000, 2000],
        3000,
        &clock,
        ctx
    );
    
    assert_single_execution(&params);
    
    destroy(params);
    destroy(clock);
}