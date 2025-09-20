#[test_only]
module account_actions::currency_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin, TreasuryCap, CoinMetadata},
    url,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self as account, Account},
    owned,
    deps,
    intents,
};
use account_actions::{
    currency,
    currency_intents,
    vesting::{Self, Vesting},
    transfer as acc_transfer,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct CURRENCY_INTENTS_TESTS has drop {}
public struct DummyIntent() has drop;

// Define Config and Outcome directly in the file
public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config>, Clock, TreasuryCap<CURRENCY_INTENTS_TESTS>, CoinMetadata<CURRENCY_INTENTS_TESTS>) {
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

    // Create account using account_protocol
    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
    let account = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // create TreasuryCap and CoinMetadata
    let (treasury_cap, metadata) = coin::create_currency(
        CURRENCY_INTENTS_TESTS {}, 
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

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config>, clock: Clock, metadata: CoinMetadata<CURRENCY_INTENTS_TESTS>) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    destroy(metadata);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_request_execute_disable_rules() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_disable_rules<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        true,
        true,
        true,
        true,
        true,
        true,
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency_intents::execute_disable_rules<Config, Outcome, CURRENCY_INTENTS_TESTS>(&mut executable, &mut account);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    currency::delete_disable<CURRENCY_INTENTS_TESTS>(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<Config, CURRENCY_INTENTS_TESTS>(&account);
    assert!(lock.can_mint() == false);
    assert!(lock.can_burn() == false);
    assert!(lock.can_update_name() == false);
    assert!(lock.can_update_symbol() == false);
    assert!(lock.can_update_description() == false);
    assert!(lock.can_update_icon() == false);

    end(scenario, extensions, account, clock, metadata);
}

#[test] 
fun test_request_execute_mint_and_keep() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let key = b"dummy".to_string();
    let addr = account.addr();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_mint_and_transfer<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[5],
        vector[addr],
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency_intents::execute_mint_and_transfer<_, Outcome, CURRENCY_INTENTS_TESTS>(&mut executable, &mut account, scenario.ctx());
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<_, CURRENCY_INTENTS_TESTS>(&account);
    let supply = currency::coin_type_supply<_, CURRENCY_INTENTS_TESTS>(&account);
    assert!(supply == 5);
    assert!(lock.total_minted() == 5);
    assert!(lock.total_burned() == 0);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_mint_and_keep_with_max_supply() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(5));

    let key = b"dummy".to_string();
    let addr = account.addr();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_mint_and_transfer<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[5],
        vector[addr],
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency_intents::execute_mint_and_transfer<_, Outcome, CURRENCY_INTENTS_TESTS>(&mut executable, &mut account, scenario.ctx());
    account.confirm_execution(executable);

    let lock = currency::borrow_rules<_, CURRENCY_INTENTS_TESTS>(&account);
    let supply = currency::coin_type_supply<_, CURRENCY_INTENTS_TESTS>(&account);
    assert!(supply == 5);
    assert!(lock.total_minted() == 5);
    assert!(lock.total_burned() == 0);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_withdraw_and_burn() {
    let (mut scenario, extensions, mut account, clock, mut cap, metadata) = start();
    // create cap, mint and transfer coin to Account
    let coin = cap.mint(5, scenario.ctx());
    assert!(cap.total_supply() == 5);

    account.keep(coin);
    scenario.next_tx(OWNER);
    let receiving = ts::most_recent_receiving_ticket<Coin<CURRENCY_INTENTS_TESTS>>(&object::id(&account));

    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_withdraw_and_burn<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        5,
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency_intents::execute_withdraw_and_burn<_, Outcome, CURRENCY_INTENTS_TESTS>(&mut executable, &mut account, receiving);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    owned::delete_withdraw_coin(&mut expired, &mut account);
    currency::delete_burn<CURRENCY_INTENTS_TESTS>(&mut expired);
    expired.destroy_empty();

    let lock = currency::borrow_rules<_, CURRENCY_INTENTS_TESTS>(&account);
    let supply = currency::coin_type_supply<_, CURRENCY_INTENTS_TESTS>(&account);
    assert!(supply == 0);
    assert!(lock.total_minted() == 0);
    assert!(lock.total_burned() == 5);

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_update_metadata() {
    let (mut scenario, extensions, mut account, clock, cap, mut metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_update_metadata<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        option::some(b"NEW".to_ascii_string()),
        option::some(b"New".to_string()),
        option::some(b"new".to_string()),
        option::some(b"https://new.com".to_ascii_string()),
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency_intents::execute_update_metadata<Config, Outcome, CURRENCY_INTENTS_TESTS>(&mut executable, &mut account, &mut metadata);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    currency::delete_update<CURRENCY_INTENTS_TESTS>(&mut expired);
    expired.destroy_empty();

    assert!(metadata.get_symbol() == b"NEW".to_ascii_string());
    assert!(metadata.get_name() == b"New".to_string());
    assert!(metadata.get_description() == b"new".to_string());
    assert!(metadata.get_icon_url().extract() == url::new_unsafe_from_bytes(b"https://new.com"));

    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_mint_and_transfer() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_mint_and_transfer<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[1, 2, 3],
        vector[@0x1, @0x2, @0x3],
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    // loop over execute_mint_and_transfer to execute each action
    3u64.do!(|_| {
        currency_intents::execute_mint_and_transfer<_, Outcome, CURRENCY_INTENTS_TESTS>(&mut executable, &mut account, scenario.ctx());
    });
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<CURRENCY_INTENTS_TESTS>>(@0x1);
    assert!(coin1.value() == 1);
    let coin2 = scenario.take_from_address<Coin<CURRENCY_INTENTS_TESTS>>(@0x2);
    assert!(coin2.value() == 2);
    let coin3 = scenario.take_from_address<Coin<CURRENCY_INTENTS_TESTS>>(@0x3);
    assert!(coin3.value() == 3);

    destroy(coin1);
    destroy(coin2);
    destroy(coin3);
    end(scenario, extensions, account, clock, metadata);
}

#[test]
fun test_request_execute_mint_and_vest() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_mint_and_vest<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    currency_intents::execute_mint_and_vest<_, Outcome, CURRENCY_INTENTS_TESTS>(&mut executable, &mut account, scenario.ctx());
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    currency::delete_mint<CURRENCY_INTENTS_TESTS>(&mut expired);
    vesting::delete_vest(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let stream = scenario.take_shared<Vesting<CURRENCY_INTENTS_TESTS>>();
    assert!(stream.balance_value() == 5);
    assert!(stream.last_claimed() == 1);
    assert!(stream.start_timestamp() == 1);
    assert!(stream.end_timestamp() == 2);
    assert!(stream.recipient() == @0x1);

    destroy(stream);
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::EAmountsRecipentsNotSameLength)]
fun test_error_request_mint_and_transfer_not_same_length() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_mint_and_transfer<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[1, 2, 3],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::EMaxSupply)]
fun test_error_request_mint_and_transfer_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let auth = account.new_auth(version::current(), DummyIntent());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_mint_and_transfer<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[1, 2, 3],
        vector[@0x1, @0x2, @0x3],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::ECannotUpdateSymbol)]
fun test_error_new_update_symbol_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_symbol<_, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_update_metadata<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        Outcome {},
        option::some(b"NEW".to_ascii_string()),
        option::none(),
        option::none(),
        option::none(),
        scenario.ctx()
    );
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::ECannotUpdateName)]
fun test_error_new_update_name_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_name<_, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_update_metadata<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        Outcome {},
        option::none(),
        option::some(b"New".to_string()),
        option::none(),
        option::none(),
        scenario.ctx()
    );
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::ECannotUpdateDescription)]
fun test_error_new_update_description_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_description<_, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_update_metadata<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        Outcome {},
        option::none(),
        option::none(),
        option::some(b"new".to_string()),
        option::none(),
        scenario.ctx()
    );
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::ECannotUpdateIcon)]
fun test_error_new_update_icon_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_update_icon<_, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_update_metadata<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        Outcome {},
        option::none(),
        option::none(),
        option::none(),
        option::some(b"https://new.com".to_ascii_string()),
        scenario.ctx()
    );
    
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::EBurnDisabled)]
fun test_error_new_burn_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());    

    currency::toggle_can_burn<_, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(   
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_withdraw_and_burn<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        Outcome {},
        5,
        scenario.ctx()
    );
    
    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::EMintDisabled)]
fun test_error_new_mint_disabled() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::none());

    currency::toggle_can_mint<_, CURRENCY_INTENTS_TESTS>(&mut account);

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_mint_and_transfer<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        Outcome {},
        vector[5],
        vector[@0x1],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}

#[test, expected_failure(abort_code = currency_intents::EMaxSupply)]
fun test_error_new_mint_too_many() {
    let (mut scenario, extensions, mut account, clock, cap, metadata) = start();
    let auth = account.new_auth(version::current(), DummyIntent());
    currency::lock_cap(auth, &mut account, cap, option::some(4));

    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    currency_intents::request_mint_and_transfer<Config, Outcome, CURRENCY_INTENTS_TESTS>(
        auth, 
        &mut account, 
        params,
        Outcome {},
        vector[5],
        vector[@0x1],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, metadata);
}