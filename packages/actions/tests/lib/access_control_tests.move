#[test_only]
module account_actions::access_control_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    intents::{Self, Intent},
    deps,
    metadata,
};
use account_actions::{
    version,
    access_control,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;
public struct Witness() has copy, drop;

public struct Cap has key, store { id: UID }
public struct WrongCap has store {}

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"account_protocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"account_actions".to_string(), @account_actions, 1);

    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let metadata = metadata::empty();
    let account = account::new(Config {}, metadata, deps, version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

fun cap(scenario: &mut Scenario): Cap {
    Cap { id: object::new(scenario.ctx()) }
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &Account<Config>, 
    clock: &Clock,
): Intent<Outcome> {
    let params = intents::new_params(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        clock,
        scenario.ctx()
    );
    account.create_intent(
        params,
        Outcome {},
        b"".to_string(),
        version::current(),
        DummyIntent(),
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock_cap() {
    let (mut scenario, extensions, mut account, clock) = start();

    assert!(!access_control::has_lock<Config, Cap>(&account));
    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    assert!(access_control::has_lock<Config, Cap>(&account));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_access_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    access_control::new_borrow<_, Cap, _>(&mut intent, DummyIntent());
    access_control::new_return<_, Cap, _>(&mut intent, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());

    assert!(access_control::has_lock<Config, Cap>(&account));
    let cap = access_control::do_borrow<_, _, Cap, _>(&mut executable, &mut account, version::current(), DummyIntent());
    assert!(!access_control::has_lock<Config, Cap>(&account));
    // do something with the cap
    access_control::do_return(&mut executable, &mut account, cap, version::current(), DummyIntent());
    assert!(access_control::has_lock<Config, Cap>(&account));

    account.confirm_execution(executable);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_access_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    access_control::new_borrow<_, Cap, _>(&mut intent, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    access_control::delete_borrow<Cap>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

/// Test error: cannot return wrong cap type because of type args

#[test, expected_failure(abort_code = access_control::ENoReturn)]
fun test_error_no_return_action() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    access_control::new_borrow<_, Cap, _>(&mut intent, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());

    let cap = access_control::do_borrow<_, _, Cap, _>(&mut executable, &mut account, version::current(), DummyIntent());

    destroy(executable);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_return_to_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    access_control::new_borrow<_, Cap, _>(&mut intent, DummyIntent());
    access_control::new_return<_, Cap, _>(&mut intent, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());

    let cap = access_control::do_borrow<_, _, Cap, _>(&mut executable, &mut account, version::current(), DummyIntent());
    // create other account
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let metadata = metadata::empty();
    let mut account2 = account::new(Config {}, metadata, deps, version::current(), Witness(), scenario.ctx());
    access_control::do_return(&mut executable, &mut account2, cap, version::current(), DummyIntent());
    account.confirm_execution(executable);

    destroy(account2);
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in account_protocol tests

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_access_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    access_control::new_borrow<_, Cap, _>(&mut intent, DummyIntent());
    access_control::new_return<_, Cap, _>(&mut intent, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    // create other account and lock same type of cap
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let metadata = metadata::empty();
    let mut account2 = account::new(Config {}, metadata, deps, version::current(), Witness(), scenario.ctx());
    let auth = account2.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account2, cap(&mut scenario));
    
    let cap = access_control::do_borrow<_, _, Cap, _>(&mut executable, &mut account2, version::current(), DummyIntent());

    destroy(account2);
    destroy(executable);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_access_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    access_control::new_borrow<_, Cap, _>(&mut intent, DummyIntent());
    access_control::new_return<_, Cap, _>(&mut intent, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    
    let cap = access_control::do_borrow<_, _, Cap, _>(&mut executable, &mut account, version::current(), WrongWitness());

    destroy(executable);
    destroy(cap);
    end(scenario, extensions, account, clock);
}