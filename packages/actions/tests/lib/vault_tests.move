#[test_only]
module account_actions::vault_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin,
    sui::SUI,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    intents::{Self, Intent},
    deps,
};
use account_actions::{
    version,
    vault,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct VAULT_TESTS has drop {}

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

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
    let account = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
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
fun test_open_vault() {
    let (mut scenario, extensions, mut account, clock) = start();

    assert!(!vault::has_vault(&account, b"Degen".to_string()));
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(vault::has_vault(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, VAULT_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<VAULT_TESTS>(5, scenario.ctx())
    );

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_exists<SUI>());
    assert!(vault.coin_type_value<SUI>() == 10);
    assert!(vault.coin_type_exists<VAULT_TESTS>());
    assert!(vault.coin_type_value<VAULT_TESTS>() == 5);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_close_vault() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(vault::has_vault(&account, b"Degen".to_string()));

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vault::new_spend<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    let (_, mut executable) = account.create_executable(b"dummy".to_string(), &clock, version::current(), DummyIntent());
    let coin = vault::do_spend<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable);

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::close(auth, &mut account, b"Degen".to_string());
    assert!(!vault::has_vault(&account, b"Degen".to_string()));

    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vault::new_deposit<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    vault::do_deposit<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(5, scenario.ctx()),
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_value<SUI>() == 5);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_flow_joining_balances() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string(); 

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vault::new_deposit<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    vault::do_deposit<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(5, scenario.ctx()),
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_value<SUI>() == 10);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_flow_multiple_coins() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string(); 

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, VAULT_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<VAULT_TESTS>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vault::new_deposit<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    vault::do_deposit<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(5, scenario.ctx()),
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.size() == 2);
    assert!(vault.coin_type_value<SUI>() == 5);
    assert!(vault.coin_type_value<VAULT_TESTS>() == 5);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vault::new_deposit<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        2,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    vault::delete_deposit<SUI>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_spend_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vault::new_spend<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        2,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    let coin = vault::do_spend<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable);

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_value<SUI>() == 3);
    assert!(coin.value() == 2);

    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_spend_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vault::new_spend<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        2,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    vault::delete_spend<SUI>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vault::EVaultNotEmpty)]
fun test_error_close_not_empty() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::deposit<Config, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = account.new_auth(version::current(), DummyIntent());
    vault::close(auth, &mut account, b"Degen".to_string());

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in account_protocol tests

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_update_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    vault::new_spend<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        2,
        DummyIntent(),
    );
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    let coin = vault::do_spend<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_update_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vault::new_spend<_, SUI, _>(
        &mut intent, 
        b"Degen".to_string(),
        2,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    let coin = vault::do_spend<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongWitness(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}
