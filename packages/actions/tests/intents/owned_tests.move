#[test_only]
module account_actions::owned_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    owned,
    deps,
    intents,
};
use account_actions::{
    owned_intents,
    vault,
    vesting::{Self, Vesting},
    transfer as acc_transfer,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Witness() has drop;

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
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
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

fun send_coin(addr: address, amount: u64, scenario: &mut Scenario): ID {
    let coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    let id = object::id(&coin);
    transfer::public_transfer(coin, addr);
    
    scenario.next_tx(OWNER);
    id
}

// === Tests ===

#[test]
fun test_request_execute_transfer_to_vault() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    vault::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let id = send_coin(account.addr(), 1, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(   
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    owned_intents::request_withdraw_and_transfer_to_vault<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        params,
        outcome, 
        1,
        b"Degen".to_string(),
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    owned_intents::execute_withdraw_and_transfer_to_vault<Config, Outcome, SUI>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id));
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    owned::delete_withdraw_coin<_, SUI>(&mut expired, &mut account);
    vault::delete_deposit<SUI>(&mut expired);
    expired.destroy_empty();

    let vault = vault::borrow_vault(&account, b"Degen".to_string());
    assert!(vault.coin_type_exists<SUI>());
    assert!(vault.coin_type_value<SUI>() == 1);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_transfer_objects() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id1 = send_coin(account.addr(), 1, &mut scenario);
    let id2 = send_coin(account.addr(), 2, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    owned_intents::request_withdraw_objects_and_transfer<Config, Outcome>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[id1, id2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    // loop over execute_transfer to execute each action
    owned_intents::execute_withdraw_object_and_transfer<_, Outcome, Coin<SUI>>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id1));
    owned_intents::execute_withdraw_object_and_transfer<_, Outcome, Coin<SUI>>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id2));
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    owned::delete_withdraw_object(&mut expired, &mut account);
    acc_transfer::delete_transfer(&mut expired);
    owned::delete_withdraw_object(&mut expired, &mut account);
    acc_transfer::delete_transfer(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(@0x1);
    assert!(coin1.value() == 1);
    let coin2 = scenario.take_from_address<Coin<SUI>>(@0x2);
    assert!(coin2.value() == 2);

    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_transfer_coins() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id1 = send_coin(account.addr(), 1, &mut scenario);
    let id2 = send_coin(account.addr(), 2, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    owned_intents::request_withdraw_coin_and_transfer<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[1, 2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    // loop over execute_transfer to execute each action
    owned_intents::execute_withdraw_coin_and_transfer<_, Outcome, SUI>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id1));
    owned_intents::execute_withdraw_coin_and_transfer<_, Outcome, SUI>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id2));
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    owned::delete_withdraw_coin<_, SUI>(&mut expired, &mut account);
    acc_transfer::delete_transfer(&mut expired);
    owned::delete_withdraw_coin<_, SUI>(&mut expired, &mut account);
    acc_transfer::delete_transfer(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(@0x1);
    assert!(coin1.value() == 1);
    let coin2 = scenario.take_from_address<Coin<SUI>>(@0x2);
    assert!(coin2.value() == 2);

    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_vesting() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    owned_intents::request_withdraw_and_vest<Config, Outcome, SUI>(
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

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    owned_intents::execute_withdraw_and_vest<Config, Outcome, SUI>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id), scenario.ctx());
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(key);
    owned::delete_withdraw_coin<_, SUI>(&mut expired, &mut account);
    vesting::delete_vest(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let stream = scenario.take_shared<Vesting<SUI>>();
    assert!(stream.balance_value() == 5);
    assert!(stream.last_claimed() == 1);
    assert!(stream.start_timestamp() == 1);
    assert!(stream.end_timestamp() == 2);
    assert!(stream.recipient() == @0x1);

    destroy(stream);
    end(scenario, extensions, account, clock);
} 

#[test, expected_failure(abort_code = owned_intents::EObjectsRecipientsNotSameLength)]
fun test_error_request_transfer_objects_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    owned_intents::request_withdraw_objects_and_transfer<Config, Outcome>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[@0x1D.to_id()],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = owned_intents::ECoinsRecipientsNotSameLength)]
fun test_error_request_transfer_coins_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    owned_intents::request_withdraw_coin_and_transfer<Config, Outcome, SUI>(
        auth, 
        &mut account, 
        params,
        outcome, 
        vector[1, 2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}
