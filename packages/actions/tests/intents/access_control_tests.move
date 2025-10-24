#[test_only]
module account_actions::access_control_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    deps,
    intents,
};
use account_actions::{
    access_control_intents,
    access_control,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Cap has key, store { id: UID }

// Define Config, Outcome, and Witness structs
public struct Witness() has copy, drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    account::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"account_protocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"account_actions".to_string(), @account_actions, 1);

    // Create account using account_protocol
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let account = account::new(Config {}, deps, version::current(), Witness(), scenario.ctx());
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

// === Tests ===

#[test]
fun test_request_execute_borrow_cap() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    access_control_intents::request_borrow_cap<Config, Outcome, Cap>(
        auth, 
        &mut account, 
        params,
        outcome, 
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    assert!(access_control::has_lock<Config, Cap>(&account));
    let cap = access_control_intents::execute_borrow_cap<Config, Outcome, Cap>(&mut executable, &mut account);
    assert!(!access_control::has_lock<Config, Cap>(&account));
    // do something with the cap
    access_control_intents::execute_return_cap<_, Outcome, _>(&mut executable, &mut account, cap);
    assert!(access_control::has_lock<Config, Cap>(&account)); 
    
    account.confirm_execution(executable);
    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    access_control::delete_borrow<Cap>(&mut expired);
    access_control::delete_return<Cap>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control_intents::ENoLock)]
fun test_error_request_borrow_cap_no_lock() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    access_control_intents::request_borrow_cap<Config, Outcome, Cap>(
        auth, 
        &mut account, 
        params,
        outcome, 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}
