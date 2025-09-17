#[test_only]
module account_actions::package_upgrade_tests;

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
    intents::{Self, Intent},
    deps,
};
use account_actions::{
    version,
    package_upgrade,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

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

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &Account<Config>, 
    clock: &Clock,
): Intent<Outcome> {
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, clock, scenario.ctx()
    );
    account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(), 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock() {
    let (scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    assert!(package_upgrade::has_cap(&account, b"Degen".to_string()));
    let cap = package_upgrade::borrow_cap(&account, @0x1);
    assert!(cap.package() == @0x1.to_id());

    let time_delay = package_upgrade::get_time_delay(&account, b"Degen".to_string());
    assert!(time_delay == 1000);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_upgrade_flow() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_upgrade(&mut intent, b"Degen".to_string(), b"", DummyIntent());
    package_upgrade::new_commit(&mut intent, b"Degen".to_string(), DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    clock.increment_for_testing(1000);

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    let ticket = package_upgrade::do_upgrade<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    package_upgrade::do_commit<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        receipt, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_additive() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_restrict(&mut intent, b"Degen".to_string(), 128, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    package_upgrade::do_restrict<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    let cap = package_upgrade::borrow_cap(&account, @0x1);
    assert!(cap.policy() == 128);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_deps_only() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_restrict(&mut intent, b"Degen".to_string(), 192, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    package_upgrade::do_restrict<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    let cap = package_upgrade::borrow_cap(&account, @0x1);
    assert!(cap.policy() == 192);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_immutable() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_restrict(&mut intent, b"Degen".to_string(), 255, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    package_upgrade::do_restrict<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    assert!(!package_upgrade::has_cap(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_upgrade_expired() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_upgrade(&mut intent, b"Degen".to_string(), b"", DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    package_upgrade::delete_upgrade(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_expired() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_restrict(&mut intent, b"Degen".to_string(), 128, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    package_upgrade::delete_restrict(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_upgrade_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    package_upgrade::new_upgrade(&mut intent, b"Degen".to_string(), b"", DummyIntent());
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    let ticket = package_upgrade::do_upgrade<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );
 
    destroy(account2);
    destroy(executable);
    destroy(ticket);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_upgrade_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_upgrade(&mut intent, b"Degen".to_string(), b"", DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    let ticket = package_upgrade::do_upgrade<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    destroy(ticket);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_confirm_upgrade_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 0);
    let auth = account2.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account2, package::test_publish(@0x1.to_id(), scenario.ctx()), b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    package_upgrade::new_upgrade(&mut intent, b"Degen".to_string(), b"", DummyIntent());
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    let ticket = package_upgrade::do_upgrade<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    package_upgrade::do_commit<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        receipt, 
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_confirm_upgrade_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 0);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_upgrade(&mut intent, b"Degen".to_string(), b"", DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    let ticket = package_upgrade::do_upgrade<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    package_upgrade::do_commit<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        receipt, 
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_restrict_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    package_upgrade::new_upgrade(&mut intent, b"Degen".to_string(), b"", DummyIntent());
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    package_upgrade::do_restrict<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_restrict_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    package_upgrade::new_upgrade(&mut intent, b"Degen".to_string(), b"", DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    package_upgrade::do_restrict<_, Outcome, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}
