#[test_only]
module account_protocol::account_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario as ts,
    clock,
};
use account_protocol::{
    account,
    intents,
    deps,
    version,
    version_witness,
};

// === Constants ===

const OWNER: address = @0xCAFE;
const ALICE: address = @0xA11CE;

// === Structs ===

public struct Witness() has drop;
public struct DummyIntent() has copy, drop;
public struct WrongWitness() has drop;

public struct Key has copy, drop, store {}
public struct Data has store {
    inner: bool
}
public struct Asset has key, store {
    id: UID,
}

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Tests ===

#[test]
fun test_create_and_share_account() {
    let mut scenario = ts::begin(OWNER);
    let account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    transfer::public_share_object(account);

    ts::end(scenario);
}

#[test]
fun test_keep_object() {
    let mut scenario = ts::begin(OWNER);
    let account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.keep(Asset { id: object::new(scenario.ctx()) });
    scenario.next_tx(OWNER);
    let Asset { id } = scenario.take_from_address<Asset>(account.addr());
    id.delete();

    destroy(account);
    ts::end(scenario);
}

#[test]
fun test_account_getters() {
    let mut scenario = ts::begin(OWNER);
    let account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    assert!(account.addr() == object::id(&account).to_address());
    assert!(account.metadata().length() == 0);
    assert!(account.deps().contains_name(b"account_protocol".to_string()));
    assert!(account.intents().length() == 0);
    assert!(account.config() == Config {});

    destroy(account);
    ts::end(scenario);
}

#[test]
fun test_intent_create_execute_flow() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (outcome, executable) = account.create_executable<Config, Outcome, Witness>(b"one".to_string(), &clock, version::current(), Witness());
    assert!(executable.intent().execution_times().length() == 0);
    account.confirm_execution<Config, Outcome>(executable);
    assert!(account.intents().length() == 1);
    let expired = account.destroy_empty_intent<Config, Outcome>(b"one".to_string());
    assert!(account.intents().length() == 0);

    destroy(expired);
    destroy(outcome);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test]
fun test_anyone_can_execute_intent() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    scenario.next_tx(ALICE);
    let (outcome, executable) = account.create_executable<Config, Outcome, Witness>(b"one".to_string(), &clock, version::current(), Witness());
    
    destroy(outcome);
    destroy(executable);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test]
fun test_intent_delete_flow() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());    

    assert!(account.intents().length() == 1);
    let expired = account.delete_expired_intent<Config, Outcome>(b"one".to_string(), &clock);
    assert!(account.intents().length() == 0);
    expired.destroy_empty();
    
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test]
fun test_managed_data() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_data(Key {}, Data { inner: true }, version::current());
    account.has_managed_data(Key {});
    let data: &Data = account.borrow_managed_data(Key {}, version::current());
    assert!(data.inner == true);
    let data: &mut Data = account.borrow_managed_data_mut(Key {}, version::current());
    assert!(data.inner == true);
    let Data { .. } = account.remove_managed_data(Key {}, version::current());

    destroy(account);
    ts::end(scenario);
}

#[test]
fun test_managed_assets() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_asset(Key {}, Asset { id: object::new(scenario.ctx()) }, version::current());
    account.has_managed_asset(Key {});
    let _asset: &Asset = account.borrow_managed_asset(Key {}, version::current());
    let _asset: &mut Asset = account.borrow_managed_asset_mut(Key {}, version::current());
    let Asset { id } = account.remove_managed_asset(Key {}, version::current());
    id.delete();

    destroy(account);
    ts::end(scenario);
}

#[test]
fun test_receive_object() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.keep(Asset { id: object::new(scenario.ctx()) });
    scenario.next_tx(OWNER);
    let id = object::id(&account);
    let Asset { id } = account.receive(ts::most_recent_receiving_ticket<Asset>(&id));
    id.delete();

    destroy(account);
    ts::end(scenario);
}

#[test]
#[allow(unused_mut_ref)]
fun test_account_getters_mut() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    assert!(account.metadata_mut(version::current()).length() == 0);
    assert!(account.deps_mut(version::current()).contains_name(b"account_protocol".to_string()));
    assert!(account.intents_mut(version::current(), Witness()).length() == 0);
    assert!(account.config_mut(version::current(), Witness()) == &mut Config {});

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = account::EWrongAccount)]
fun test_error_cannot_verify_wrong_account() {
    let mut scenario = ts::begin(OWNER);
    let account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    
    let auth = account.new_auth(version::current(), Witness());
    let deps = deps::new_for_testing();
    let account2 = account::new(Config {}, deps, version::current(), Witness(), scenario.ctx());
    account2.verify(auth);

    destroy(account2);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_create_intent_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version_witness::new_for_testing(@0xDE9), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_insert_intent_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version_witness::new_for_testing(@0xDE9), DummyIntent());

    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_insert_intent_with_wrong_account() {
    let mut scenario = ts::begin(OWNER);
    let account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let deps = deps::new_for_testing();
    let mut account2 = account::new(Config {}, deps, version::current(), Witness(), scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    
    account2.insert_intent(intent, version::current(), DummyIntent());

    destroy(account2);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_insert_intent_with_wrong_witness() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );    
    account.insert_intent(intent, version::current(), WrongWitness());

    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_cannot_confirm_execution_with_wrong_account() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let deps = deps::new_for_testing();
    let mut account2 = account::new(Config {}, deps, version::current(), Witness(), scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, executable) = account.create_executable<Config, Outcome, Witness>(b"one".to_string(), &clock, version::current(), Witness());
    account2.confirm_execution<Config, Outcome>(executable);

    destroy(account2);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = account::EActionsRemaining)]
fun test_error_cannot_confirm_execution_before_all_actions_executed() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let mut intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    intent.add_action(Data { inner: true }, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let (outcome, executable) = account.create_executable<Config, Outcome, Witness>(b"one".to_string(), &clock, version::current(), Witness());
    account.confirm_execution<Config, Outcome>(executable);

    destroy(outcome);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = account::ECantBeRemovedYet)]
fun test_error_cannot_destroy_intent_without_executing() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    let expired = account.destroy_empty_intent<Config, Outcome>(b"one".to_string());

    destroy(expired);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = account::EHasntExpired)]
fun test_error_cannot_delete_intent_not_expired() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    let expired = account.delete_expired_intent<Config, Outcome>(b"one".to_string(), &clock);

    destroy(expired);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}


#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_managed_asset_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_data(Key {}, Data { inner: true }, version_witness::new_for_testing(@0xDE9));

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_managed_asset_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_data(Key {}, Data { inner: true }, version::current());
    let asset: &Data = account.borrow_managed_data(Key {}, version_witness::new_for_testing(@0xDE9));
    assert!(asset.inner == true);

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_mut_managed_asset_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_data(Key {}, Data { inner: true }, version::current());
    let asset: &mut Data = account.borrow_managed_data_mut(Key {}, version_witness::new_for_testing(@0xDE9));
    assert!(asset.inner == true);

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_remove_managed_asset_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_data(Key {}, Data { inner: true }, version::current());
    let Data { .. } = account.remove_managed_data(Key {}, version_witness::new_for_testing(@0xDE9));

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_managed_object_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_asset(Key {}, Asset { id: object::new(scenario.ctx()) }, version_witness::new_for_testing(@0xDE9));

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_managed_object_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_asset(Key {}, Asset { id: object::new(scenario.ctx()) }, version::current());
    let asset: &Asset = account.borrow_managed_asset(Key {}, version_witness::new_for_testing(@0xDE9));
    assert!(asset.id.to_inner() == object::id(&account));

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_mut_managed_object_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_asset(Key {}, Asset { id: object::new(scenario.ctx()) }, version::current());
    let asset: &mut Asset = account.borrow_managed_asset_mut(Key {}, version_witness::new_for_testing(@0xDE9));
    assert!(asset.id.to_inner() == object::id(&account));

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_remove_managed_object_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    account.add_managed_asset(Key {}, Asset { id: object::new(scenario.ctx()) }, version::current());
    let Asset { id } = account.remove_managed_asset(Key {}, version_witness::new_for_testing(@0xDE9));
    id.delete();

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_new_auth_not_called_from_not_dep() {
    let mut scenario = ts::begin(OWNER);
    let account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    let auth = account.new_auth(version_witness::new_for_testing(@0xDE9), Witness());
    account.verify(auth);

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = account::ENotCalledFromConfigModule)]
fun test_error_new_auth_not_called_from_config_module() {
    let mut scenario = ts::begin(OWNER);
    let account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());

    let auth = account.new_auth(version::current(), account::not_config_witness());
    account.verify(auth);

    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_execute_intent_from_not_dependent_package() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    let (_, executable) = account.create_executable<Config, Outcome, Witness>(b"one".to_string(), &clock, version_witness::new_for_testing(@0xDE9), Witness());

    destroy(executable);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = account::ENotCalledFromConfigModule)]
fun test_error_cannot_execute_intent_not_called_from_config_module() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    let (_, executable) = account.create_executable<Config, Outcome, account::Witness>(b"one".to_string(), &clock, version::current(), account::not_config_witness());

    destroy(executable);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = account::ECantBeExecutedYet)]
fun test_error_cannot_execute_intent_before_execution_time() {
    let mut scenario = ts::begin(OWNER);
    let mut account = account::new(Config {}, deps::new_for_testing(), version::current(), Witness(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    let params = intents::new_params(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[1],
        1, 
        &clock,
        scenario.ctx()
    );
    let intent = account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(),
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    let (_, executable) = account.create_executable<Config, Outcome, Witness>(b"one".to_string(), &clock, version::current(), Witness());

    destroy(executable);
    destroy(clock);
    destroy(account);
    ts::end(scenario);
}