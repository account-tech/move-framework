#[test_only]
module account_protocol::owned_tests;

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
    intents::{Self, Intent},
    deps,
    owned,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Witness() has drop;
public struct DummyIntent() has drop;
public struct WrongWitness() has drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

public struct Obj has key, store {
    id: UID,
}

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
    extensions.add(&cap, b"AccountMultisig".to_string(), @0x1, 1);
    extensions.add(&cap, b"account_actions".to_string(), @0x2, 1);
    // Account generic types are dummy types (bool, bool)
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string()]);
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

fun send_object(addr: address, scenario: &mut Scenario): ID {
    let uid = object::new(scenario.ctx());
    let id = uid.to_inner();

    let obj = Obj { id: uid };
    transfer::public_transfer(obj, addr);
    
    scenario.next_tx(OWNER);
    id
}

fun send_coin(addr: address, amount: u64, scenario: &mut Scenario): ID {
    let coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    let id = object::id(&coin);
    transfer::public_transfer(coin, addr);
    
    scenario.next_tx(OWNER);
    id
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &Account<Config>, 
    clock: &Clock,
): Intent<Outcome> {
        let params = intents::new_params(
        b"dummy".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        clock,
        scenario.ctx()
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
fun test_withdraw_object_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_object(account.addr(), &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_object(&mut intent, &mut account, id, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    let obj = owned::do_withdraw_object<_, Outcome, Obj, _>(
        &mut executable,
        &mut account, 
        ts::receiving_ticket_by_id<Obj>(id),
        DummyIntent(),
    );
    account.confirm_execution(executable);

    assert!(obj.id.to_inner() == id);
    destroy(obj);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_withdraw_object_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let id = send_object(account.addr(), &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_object(&mut intent, &mut account, id, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    owned::delete_withdraw_object(&mut expired, &mut account);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_withdraw_coin_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_coin<_, _, SUI, _>(&mut intent, &mut account, 5, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    let coin = owned::do_withdraw_coin<_, Outcome, SUI, _>(
        &mut executable,
        &mut account, 
        vector[ts::receiving_ticket_by_id<Coin<SUI>>(id)],
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable);

    assert!(coin.value() == 5);
    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_withdraw_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let _id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_coin<_, _, SUI, _>(&mut intent, &mut account, 5, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    owned::delete_withdraw_coin<_, SUI>(&mut expired, &mut account);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = owned::EWrongObject)]
fun test_error_do_withdraw_wrong_object() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_object(account.addr(), &mut scenario);
    let not_id = send_object(account.addr(), &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_object(&mut intent, &mut account, id, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    let obj = owned::do_withdraw_object<_, Outcome, Obj, _>(
        &mut executable,
        &mut account, 
        ts::receiving_ticket_by_id<Obj>(not_id),
        DummyIntent(),
    );
    account.confirm_execution(executable);

    destroy(obj);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = owned::EWrongCoinType)]
fun test_error_do_withdraw_wrong_coin_type() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let _id = send_coin(account.addr(), 5, &mut scenario);

    let coin = coin::mint_for_testing<Witness>(5, scenario.ctx());
    let id = object::id(&coin);
    transfer::public_transfer(coin, account.addr());
    scenario.next_tx(OWNER);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_coin<_, _, SUI, _>(&mut intent, &mut account, 5, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    let coin = owned::do_withdraw_coin<_, Outcome, Witness, _>(
        &mut executable,
        &mut account, 
        vector[ts::receiving_ticket_by_id<Coin<Witness>>(id)],
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable);

    assert!(coin.value() == 5);
    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = owned::EWrongAmount)]
fun test_error_do_withdraw_wrong_coin_amount() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_coin<_, _, SUI, _>(&mut intent, &mut account, 4, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    let coin = owned::do_withdraw_coin<_, Outcome, SUI, _>(
        &mut executable,
        &mut account, 
        vector[ts::receiving_ticket_by_id<Coin<SUI>>(id)],
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable);

    assert!(coin.value() == 5);
    destroy(coin);
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in account_protocol tests

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_withdraw_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();

    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), Witness(), scenario.ctx());
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    owned::new_withdraw_coin<_, _, SUI, _>(&mut intent, &mut account, 5, DummyIntent());
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    // try to disable from the account that didn't approve the intent
    let coin = owned::do_withdraw_coin<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        vector[ts::receiving_ticket_by_id<Coin<SUI>>(id)],
        DummyIntent(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_withdraw_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_coin<_, _, SUI, _>(&mut intent, &mut account, 5, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), Witness());
    // try to disable with the wrong witness that didn't approve the intent
    let coin = owned::do_withdraw_coin<_, Outcome, SUI, _>(
        &mut executable, 
        &mut account, 
        vector[ts::receiving_ticket_by_id<Coin<SUI>>(id)],
        WrongWitness(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_delete_withdraw_from_wrong_account() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"account_protocol".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), Witness(), scenario.ctx());

    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let _id = send_coin(account.addr(), 5, &mut scenario);

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    owned::new_withdraw_coin<_, _, SUI, _>(&mut intent, &mut account, 5, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    owned::delete_withdraw_coin<_, SUI>(&mut expired, &mut account2);
    expired.destroy_empty();

    destroy(account2);
    end(scenario, extensions, account, clock);
}