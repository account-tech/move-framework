#[test_only]
module account_actions::transfer_tests;

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
    transfer as acc_transfer,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Obj has key, store {
    id: UID
}

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
fun test_transfer_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let obj = Obj { id: object::new(scenario.ctx()) };

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_transfer::new_transfer(&mut intent, OWNER, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    acc_transfer::do_transfer<Outcome, Obj, _>(
        &mut executable, 
        obj,
        DummyIntent(),
    );
    account.confirm_execution(executable);

    scenario.next_tx(OWNER);
    assert!(scenario.has_most_recent_for_sender<Obj>());

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in account_protocol tests

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_transfer_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_transfer::new_transfer(&mut intent, OWNER, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    // try to disable with the wrong witness that didn't approve the intent
    acc_transfer::do_transfer<Outcome, _, _>(
        &mut executable, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}