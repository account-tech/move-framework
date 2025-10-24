#[test_only]
module account_protocol::config_intents_tests;

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
    config,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

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
    extensions.add(&cap, b"AccountConfig".to_string(), @0x1, 1);
    extensions.update(&cap, b"AccountConfig".to_string(), @0x11, 2);
    extensions.add(&cap, b"account_actions".to_string(), @0x2, 1);
    // add external dep
    extensions.add(&cap, b"External".to_string(), @0xABC, 1);

    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"AccountConfig".to_string()]);
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

// === Tests ===

#[test]
fun test_edit_config_metadata() {
    let (scenario, extensions, mut account, clock) = start();    
    assert!(account.metadata().length() == 0);

    let auth = account.new_auth(version::current(), Witness());
    config::edit_metadata(
        auth, 
        &mut account,
        vector[b"name".to_string()], 
        vector[b"New Name".to_string()], 
    );

    assert!(account.metadata().get(b"name".to_string()) == b"New Name".to_string());
    end(scenario, extensions, account, clock);
}

#[test]
fun test_update_extensions_to_latest() {
    let (scenario, mut extensions, mut account, clock) = start();
    assert!(account.deps().get_by_name(b"account_protocol".to_string()).version() == 1);
    extensions.update_for_testing(b"account_protocol".to_string(), @0x3, 2);

    let auth = account.new_auth(version::current(), Witness());
    config::update_extensions_to_latest(
        auth,
        &mut account,
        &extensions,
    );
    assert!(account.deps().get_by_name(b"account_protocol".to_string()).version() == 2);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_update_extensions_to_latest_with_unverified() {
    let (scenario, mut extensions, mut account, clock) = start();
    assert!(account.deps().get_by_name(b"account_protocol".to_string()).version() == 1);
    extensions.update_for_testing(b"account_protocol".to_string(), @0x3, 2);
    
    account.deps_mut(version::current()).toggle_unverified_allowed_for_testing();
    let deps_inner = deps::new_inner(&extensions, account.deps(), vector[b"account_protocol".to_string(), b"AccountConfig".to_string(), b"Other".to_string()], vector[@account_protocol, @0x1, @0x2], vector[1, 2, 1]);
    *account.deps_mut(version::current()).inner_mut() = deps_inner;

    let auth = account.new_auth(version::current(), Witness());
    config::update_extensions_to_latest(
        auth,
        &mut account,
        &extensions,
    );

    assert!(account.deps().get_by_name(b"AccountConfig".to_string()).version() == 2);
    assert!(account.deps().get_by_name(b"account_protocol".to_string()).version() == 2);
    assert!(account.deps().get_by_name(b"Other".to_string()).version() == 1);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_config_deps() {
    let (mut scenario, extensions, mut account, clock) = start();    
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    let params = intents::new_params(
        key, 
        b"".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    config::request_config_deps(
        auth, 
        &mut account, 
        params,
        Outcome {}, 
        &extensions,
        vector[b"account_protocol".to_string(), b"AccountConfig".to_string(), b"External".to_string()], 
        vector[@account_protocol, @0x11, @0xABC], 
        vector[1, 2, 1], 
        scenario.ctx()
    );
    assert!(!account.deps().contains_name(b"External".to_string()));

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    config::execute_config_deps<Config, Outcome>(&mut executable, &mut account);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<Config, Outcome>(key);
    config::delete_config_deps(&mut expired);
    expired.destroy_empty();
    
    let package = account.deps().get_by_name(b"External".to_string());
    assert!(package.addr() == @0xABC);
    assert!(package.version() == 1);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_config_deps_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();    
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    let params = intents::new_params(
        key, 
        b"".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    config::request_config_deps(
        auth, 
        &mut account, 
        params,
        Outcome {}, 
        &extensions,
        vector[b"account_protocol".to_string(), b"AccountConfig".to_string()], 
        vector[@account_protocol, @0x11], 
        vector[1, 2], 
        scenario.ctx()
    );
    
    let mut expired = account.delete_expired_intent<Config, Outcome>(key, &clock);
    config::delete_config_deps(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_toggle_unverified_allowed() {
    let (mut scenario, extensions, mut account, clock) = start();    
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    let params = intents::new_params(
        key, 
        b"".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    config::request_toggle_unverified_allowed(
        auth, 
        &mut account,
        params,
        Outcome {}, 
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    config::execute_toggle_unverified_allowed<Config, Outcome>(&mut executable, &mut account);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<Config, Outcome>(key);
    config::delete_toggle_unverified_allowed(&mut expired);
    expired.destroy_empty();
    
    assert!(account.deps().unverified_allowed() == true);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_toggle_unverified_allowed_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();    
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    let params = intents::new_params(
        key, 
        b"".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );  
    config::request_toggle_unverified_allowed(
        auth, 
        &mut account,
        params,
        Outcome {},
        scenario.ctx()
    );
    
    let mut expired = account.delete_expired_intent<Config, Outcome>(key, &clock);
    config::delete_toggle_unverified_allowed(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}