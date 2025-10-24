#[test_only]
module account_actions::currency_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, TreasuryCap, CoinMetadata},
    url,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    intents::{Self, Intent},
    deps,
};
use account_actions::{
    version,
    currency,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct CURRENCY_TESTS has drop {}

public struct Witness() has drop;
public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config>, Clock, TreasuryCap<CURRENCY_TESTS>, CoinMetadata<CURRENCY_TESTS>) {
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
    let account = account::new(Config {}, deps, version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // create TreasuryCap and CoinMetadata
    let (treasury_cap, metadata) = coin::create_currency(
        CURRENCY_TESTS {}, 
        9, 
        b"SYMBOL", 
        b"Name", 
        b"description", 
        option::some(url::new_unsafe_from_bytes(b"https://url.com")), 
        scenario.ctx()
    );
    // create world
    destroy(cap);
    (scenario, extensions, account, clock, treasury_cap, metadata)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config>, clock: Clock, metadata: CoinMetadata<CURRENCY_TESTS>) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    destroy(metadata);
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
fun test_lock_cap() {
    let (scenario, extensions, mut account, clock, cap, metadata) = start();

    assert!(!currency::has_cap<_, CURRENCY_TESTS>(&account));
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(100));
    assert!(currency::has_cap<_, CURRENCY_TESTS>(&account));

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_lock_getters() {
    let (scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(100));

    let lock = currency::borrow_rules<_, CURRENCY_TESTS>(&account);
    let supply = currency::coin_type_supply<_, CURRENCY_TESTS>(&account);
    assert!(supply == 0);
    assert!(lock.total_minted() == 0);
    assert!(lock.total_burned() == 0);
    assert!(lock.can_mint() == true);
    assert!(lock.can_burn() == true);
    assert!(lock.can_update_name() == true);
    assert!(lock.can_update_symbol() == true);
    assert!(lock.can_update_description() == true);
    assert!(lock.can_update_icon() == true);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_public_burn() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(100));

    currency::public_burn(&mut account, coin);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_disable_flow() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_disable<_, CURRENCY_TESTS, _>(
        &mut intent, 
        true,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_disable<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_mint_flow() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_mint<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    let coin = currency::do_mint<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx(),
    );
    assert!(coin.value() == 5);
    account.confirm_execution(executable);

    destroy(coin);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_burn_flow() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_burn<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_burn<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_update_flow() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_update<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable);

    assert!(metadata.get_symbol() == b"NEW".to_ascii_string());
    assert!(metadata.get_name() == b"New".to_string());
    assert!(metadata.get_description() == b"new".to_string());
    assert!(metadata.get_icon_url().extract() == url::new_unsafe_from_bytes(b"https://new.com"));

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_disable_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_disable<_, CURRENCY_TESTS, _>(
        &mut intent, 
        true,
        true,
        true,
        true,
        true,
        true,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    currency::delete_disable<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_mint_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_mint<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    currency::delete_mint<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_burn_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_burn<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    currency::delete_burn<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_update_expired() {
    let (mut scenario, extensions, mut account, mut clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    currency::delete_update<CURRENCY_TESTS>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EBurnDisabled)]
fun test_error_public_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_burn<_, CURRENCY_TESTS>(&mut account);
    currency::public_burn(&mut account, coin);

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoChange)]
fun test_error_disable_nothing() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_disable<_, CURRENCY_TESTS, _>(
        &mut intent, 
        false,
        false,
        false,
        false,
        false,
        false,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMintDisabled)]
fun test_error_do_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_mint<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    currency::toggle_can_mint<_, CURRENCY_TESTS>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    let coin = currency::do_mint<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(executable);
    destroy(coin);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EMaxSupply)]
fun test_error_do_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_mint<_, CURRENCY_TESTS, _>(
        &mut intent, 
        3,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    let mut intent = create_another_dummy_intent(&mut scenario, &account, &clock);
    currency::new_mint<_, CURRENCY_TESTS, _>(
        &mut intent, 
        3,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable1) = account.create_executable<_, Outcome, _>(b"dummy".to_string(), &clock, version::current(), DummyIntent());
    let coin1 = currency::do_mint<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable1, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx(),
    );

    let (_, mut executable2) = account.create_executable<_, Outcome, _>(b"another".to_string(), &clock, version::current(), DummyIntent());
    let coin2 = currency::do_mint<_, Outcome, CURRENCY_TESTS, _>(
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
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EWrongValue)]
fun test_error_do_burn_wrong_value() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_burn<_, CURRENCY_TESTS, _>(
        &mut intent, 
        4,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_burn<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::EBurnDisabled)]
fun test_error_do_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_burn<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    currency::toggle_can_burn<_, CURRENCY_TESTS>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_burn<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ENoChange)]
fun test_error_new_update_nothing() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateSymbol)]
fun test_error_do_update_symbol_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::none(),
        option::none(),
        option::none(),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    currency::toggle_can_update_symbol<_, CURRENCY_TESTS>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_update<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateName)]
fun test_error_do_update_name_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::none(),
        option::some(b"New".to_string()),
        option::none(),
        option::none(),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    currency::toggle_can_update_name<_, CURRENCY_TESTS>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_update<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateDescription)]
fun test_error_do_update_description_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::none(),
        option::none(),
        option::some(b"new".to_string()),
        option::none(),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    currency::toggle_can_update_description<_, CURRENCY_TESTS>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_update<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency::ECannotUpdateIcon)]
fun test_error_do_update_icon_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::none(),
        option::none(),
        option::none(),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    currency::toggle_can_update_icon<_, CURRENCY_TESTS>(&mut account);

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency::do_update<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );
    
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

// sanity checks as these are tested in account_protocol tests

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_disable_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(4));
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    currency::new_disable<_, CURRENCY_TESTS, _>(
        &mut intent, 
        true,
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
    currency::do_disable<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_disable_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_disable<_, CURRENCY_TESTS, _>(
        &mut intent, 
        true,
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
    currency::do_disable<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_mint_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    currency::new_mint<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to mint from the right account that didn't approve the intent
    let coin = currency::do_mint<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx(),
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_mint_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_mint<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    let coin = currency::do_mint<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongWitness(),
        scenario.ctx(),
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_burn_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    currency::new_burn<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    currency::do_burn<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_burn_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    let coin = cap.mint(5, scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_burn<_, CURRENCY_TESTS, _>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to burn with the wrong witness that didn't approve the intent
    currency::do_burn<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        coin,
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_update_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string(), b"account_actions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(4));
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    currency::do_update<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_update_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    currency::new_update<_, CURRENCY_TESTS, _>(
        &mut intent, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        DummyIntent(),
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    currency::do_update<_, Outcome, CURRENCY_TESTS, _>(
        &mut executable, 
        &mut account, 
        &mut metadata,
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock, metadata);
}