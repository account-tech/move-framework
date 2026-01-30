#[test_only]
module account_actions::currency_tests;

// === Imports ===

use std::unit_test::destroy;
use sui::{
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::TreasuryCap,
    coin_registry::{Self, Currency, MetadataCap},
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
    currency as acc_currency,
};

// === Constants ===

const OWNER: address = @0x0;

// === Structs ===

public struct CurrencyObj has key { 
    id: UID,
}

public struct Witness() has drop;
public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (
    Scenario,
    Extensions,
    Account<Config>,
    Clock,
    TreasuryCap<CurrencyObj>,
    Currency<CurrencyObj>,
    MetadataCap<CurrencyObj>
) {
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

    let mut registry = coin_registry::create_coin_data_registry_for_testing(scenario.ctx());
    let (currency_init, treasury_cap) = coin_registry::new_currency<CurrencyObj>(
        &mut registry,
        9,
        b"SYMBOL".to_string(),
        b"Name".to_string(),
        b"description".to_string(),
        b"https://url.com".to_string(),
        scenario.ctx()
    );
    let (currency, metadata_cap) = coin_registry::finalize_unwrap_for_testing<CurrencyObj>(currency_init, scenario.ctx());
    destroy(registry);

    // create world
    destroy(cap);
    (scenario, extensions, account, clock, treasury_cap, currency, metadata_cap)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config>, clock: Clock, currency: Currency<CurrencyObj>) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    destroy(currency);
    ts::end(scenario);
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

fun create_another_dummy_intent(
    scenario: &mut Scenario,
    account: &Account<Config>,
    clock: &Clock,
): Intent<Outcome> {
    let params = intents::new_params(
        b"another".to_string(),
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
fun test_lock_caps() {
    let (scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();

    assert!(!acc_currency::has_treasury_cap<_, CurrencyObj>(&account));
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(100));
    assert!(acc_currency::has_treasury_cap<_, CurrencyObj>(&account));

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_lock_getters() {
    let (scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(100));

    let lock = acc_currency::borrow_rules<_, CurrencyObj>(&account);
    let supply = acc_currency::coin_type_supply<_, CurrencyObj>(&account);
    assert!(supply == 0);
    assert!(lock.total_minted() == 0);
    assert!(lock.total_burned() == 0);
    assert!(lock.can_mint() == true);
    assert!(lock.can_burn() == true);
    assert!(lock.can_update_name() == true);
    assert!(lock.can_update_description() == true);
    assert!(lock.can_update_icon() == true);

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_public_burn() {
    let (mut scenario, extensions, mut account, clock, mut cap, currency, metadata_cap) = start();
    let coin = cap.mint(5, scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(100));

    acc_currency::public_burn(&mut account, coin);

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_disable_flow() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_disable<_, CurrencyObj, _>(
        &mut intent,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_currency::do_disable<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        version::current(),
        DummyIntent(),
    );
    account.confirm_execution(executable);

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_mint_flow() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_mint<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    let coin = acc_currency::do_mint<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        version::current(),
        DummyIntent(),
        scenario.ctx(),
    );
    assert!(coin.value() == 5);
    account.confirm_execution(executable);

    destroy(coin);
    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_burn_flow() {
    let (mut scenario, extensions, mut account, clock, mut cap, currency, metadata_cap) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_burn<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_currency::do_burn<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        coin,
        version::current(),
        DummyIntent(),
    );
    account.confirm_execution(executable);

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_update_flow() {
    let (mut scenario, extensions, mut account, clock, cap, mut currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_update<_, CurrencyObj, _>(
        &mut intent,
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_string()),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_currency::do_update<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        &mut currency,
        version::current(),
        DummyIntent(),
    );
    account.confirm_execution(executable);

    assert!(currency.name() == b"New".to_string());
    assert!(currency.description() == b"new".to_string());
    assert!(currency.icon_url() == b"https://new.com".to_string());

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_disable_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_disable<_, CurrencyObj, _>(
        &mut intent,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    acc_currency::delete_disable<CurrencyObj>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_mint_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_mint<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    acc_currency::delete_mint<CurrencyObj>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_burn_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_burn<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    acc_currency::delete_burn<CurrencyObj>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock, currency);
}

#[test]
fun test_update_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_update<_, CurrencyObj, _>(
        &mut intent,
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_string()),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    acc_currency::delete_update<CurrencyObj>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::EBurnDisabled)]
fun test_error_public_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, mut cap, currency, metadata_cap) = start();
    let coin = cap.mint(5, scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());

    acc_currency::toggle_can_burn<_, CurrencyObj>(&mut account);
    acc_currency::public_burn(&mut account, coin);

    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::ENoChange)]
fun test_error_disable_nothing() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_disable<_, CurrencyObj, _>(
        &mut intent,
        false,
        false,
        false,
        false,
        false,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::EMintDisabled)]
fun test_error_do_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_mint<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    acc_currency::toggle_can_mint<_, CurrencyObj>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    let coin = acc_currency::do_mint<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        version::current(),
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(executable);
    destroy(coin);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::EMaxSupply)]
fun test_error_do_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_mint<_, CurrencyObj, _>(
        &mut intent,
        3,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    let mut intent = create_another_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_mint<_, CurrencyObj, _>(
        &mut intent,
        3,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable1) = account.create_executable<_, Outcome, _>(b"dummy".to_string(), &clock, version::current(), DummyIntent());
    let coin1 = acc_currency::do_mint<_, Outcome, CurrencyObj, _>(
        &mut executable1,
        &mut account,
        version::current(),
        DummyIntent(),
        scenario.ctx(),
    );

    let (_, mut executable2) = account.create_executable<_, Outcome, _>(b"another".to_string(), &clock, version::current(), DummyIntent());
    let coin2 = acc_currency::do_mint<_, Outcome, CurrencyObj, _>(
        &mut executable2,
        &mut account,
        version::current(),
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(executable1);
    destroy(executable2);
    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::EWrongValue)]
fun test_error_do_burn_wrong_value() {
    let (mut scenario, extensions, mut account, clock, mut cap, currency, metadata_cap) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_burn<_, CurrencyObj, _>(
        &mut intent,
        4,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_currency::do_burn<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        coin,
        version::current(),
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::EBurnDisabled)]
fun test_error_do_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, mut cap, currency, metadata_cap) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_burn<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    acc_currency::toggle_can_burn<_, CurrencyObj>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_currency::do_burn<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        coin,
        version::current(),
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::ENoChange)]
fun test_error_new_update_nothing() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_update<_, CurrencyObj, _>(
        &mut intent,
        option::none(),
        option::none(),
        option::none(),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::ECannotUpdateName)]
fun test_error_do_update_name_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_update<_, CurrencyObj, _>(
        &mut intent,
        option::some(b"New".to_string()),
        option::none(),
        option::none(),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    acc_currency::toggle_can_update_name<_, CurrencyObj>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_currency::do_update<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        &mut currency,
        version::current(),
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::ECannotUpdateDescription)]
fun test_error_do_update_description_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_update<_, CurrencyObj, _>(
        &mut intent,
        option::none(),
        option::some(b"new".to_string()),
        option::none(),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    acc_currency::toggle_can_update_description<_, CurrencyObj>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_currency::do_update<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        &mut currency,
        version::current(),
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = acc_currency::ECannotUpdateIcon)]
fun test_error_do_update_icon_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut currency, metadata_cap) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_update<_, CurrencyObj, _>(
        &mut intent,
        option::none(),
        option::none(),
        option::some(b"https://new.com".to_string()),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    acc_currency::toggle_can_update_icon<_, CurrencyObj>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_currency::do_update<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        &mut currency,
        version::current(),
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

// sanity checks as these are tested in account_protocol tests

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_disable_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let metadata = metadata::empty();
    let mut account2 = account::new(Config {}, metadata, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(4));
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    acc_currency::new_disable<_, CurrencyObj, _>(
        &mut intent,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to disable from the account that didn't approve the intent
    acc_currency::do_disable<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        version::current(),
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_disable_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_disable<_, CurrencyObj, _>(
        &mut intent,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to disable with the wrong witness that didn't approve the intent
    acc_currency::do_disable<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        version::current(),
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_mint_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let metadata = metadata::empty();
    let mut account2 = account::new(Config {}, metadata, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    acc_currency::new_mint<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to mint from the right account that didn't approve the intent
    let coin = acc_currency::do_mint<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        version::current(),
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_mint_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, currency, metadata_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_mint<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    let coin = acc_currency::do_mint<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        version::current(),
        WrongWitness(),
        scenario.ctx(),
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_burn_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, mut cap, currency, metadata_cap) = start();
    let coin = cap.mint(5, scenario.ctx());
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let metadata = metadata::empty();
    let mut account2 = account::new(Config {}, metadata, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::none());
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    acc_currency::new_burn<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    acc_currency::do_burn<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        coin,
        version::current(),
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_burn_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, mut cap, currency, metadata_cap) = start();
    let coin = cap.mint(5, scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_burn<_, CurrencyObj, _>(
        &mut intent,
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to burn with the wrong witness that didn't approve the intent
    acc_currency::do_burn<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        coin,
        version::current(),
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_update_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, mut currency, metadata_cap) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let metadata = metadata::empty();
    let mut account2 = account::new(Config {}, metadata, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(4));
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    acc_currency::new_update<_, CurrencyObj, _>(
        &mut intent,
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_string()),
        DummyIntent(),
    );
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to update from the account that didn't approve the intent
    acc_currency::do_update<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        &mut currency,
        version::current(),
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_update_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, mut currency, metadata_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_currency::lock_caps(auth, &mut account, cap, option::some(metadata_cap), option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_currency::new_update<_, CurrencyObj, _>(
        &mut intent,
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_string()),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to update with the wrong witness that didn't approve the intent
    acc_currency::do_update<_, Outcome, CurrencyObj, _>(
        &mut executable,
        &mut account,
        &mut currency,
        version::current(),
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, currency);
}
