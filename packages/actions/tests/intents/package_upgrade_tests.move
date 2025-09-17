#[test_only]
module account_actions::package_upgrade_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    package::{Self, UpgradeCap},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    deps,
    intents,
};
use account_actions::{
    package_upgrade,
    package_upgrade_intents,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config>, Clock, UpgradeCap) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
    let account = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    let upgrade_cap = package::test_publish(@0x1.to_id(), scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock, upgrade_cap)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_request_execute_upgrade() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        key, 
        b"".to_string(), 
        vector[1000],
        2000, 
        &clock,
        scenario.ctx()
    );
    package_upgrade_intents::request_upgrade_package(
        auth, 
        &mut account, 
        params,
        outcome, 
        b"Degen".to_string(), 
        b"",
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());

    let ticket = package_upgrade_intents::execute_upgrade_package<_, Outcome>(&mut executable, &mut account, &clock);
    let receipt = ticket.test_upgrade();
    package_upgrade_intents::execute_commit_upgrade<_, Outcome>(&mut executable, &mut account, receipt);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    package_upgrade::delete_upgrade(&mut expired);
    package_upgrade::delete_commit(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_restrict_all() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        key, 
        b"".to_string(), 
        vector[0],
        2000, 
        &clock,
        scenario.ctx()
    );
    package_upgrade_intents::request_restrict_policy(
        auth, 
        &mut account, 
        params,
        outcome, 
        b"Degen".to_string(), 
        128, // additive
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    package_upgrade_intents::execute_restrict_policy<_, Outcome>(&mut executable, &mut account);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    package_upgrade::delete_restrict(&mut expired);
    expired.destroy_empty();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        key, 
        b"".to_string(), 
        vector[0],
        3000, 
        &clock,
        scenario.ctx()
    );
    package_upgrade_intents::request_restrict_policy(
        auth, 
        &mut account, 
        params,
        outcome, 
        b"Degen".to_string(), 
        192, // deps only
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    package_upgrade_intents::execute_restrict_policy<_, Outcome>(&mut executable, &mut account);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    package_upgrade::delete_restrict(&mut expired);
    expired.destroy_empty();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        key, 
        b"".to_string(), 
        vector[0],
        4000, 
        &clock,
        scenario.ctx()  
    );
    package_upgrade_intents::request_restrict_policy(
        auth, 
        &mut account, 
        params,
        outcome, 
        b"Degen".to_string(), 
        255, // immutable
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    package_upgrade_intents::execute_restrict_policy<_, Outcome>(&mut executable, &mut account);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    package_upgrade::delete_restrict(&mut expired);
    expired.destroy_empty();
    // lock destroyed with upgrade cap
    assert!(!package_upgrade::has_cap(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = package_upgrade_intents::EPolicyShouldRestrict)]
fun test_error_new_restrict_not_restrictive() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1000, 
        &clock,
        scenario.ctx()
    );
    package_upgrade_intents::request_restrict_policy(
        auth, 
        &mut account, 
        params,
        Outcome {},
        b"Degen".to_string(), 
        0, 
        scenario.ctx()
    );
    
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = package_upgrade_intents::EInvalidPolicy)]
fun test_error_new_restrict_invalid_policy() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0], 
        1000, 
        &clock,
        scenario.ctx()
    );
    package_upgrade_intents::request_restrict_policy(
        auth, 
        &mut account, 
        params,
        Outcome {},
        b"Degen".to_string(), 
        100, // additive
        scenario.ctx()
    );
    
    end(scenario, extensions, account, clock);
}