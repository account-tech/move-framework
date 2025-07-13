/// This is the core module managing the account Account<Config>.
/// It provides the apis to create, approve and execute intents with actions.
/// 
/// The flow is as follows:
///   1. An intent is created by stacking actions into it. 
///      Actions are pushed from first to last, they must be executed then destroyed in the same order.
///   2. When the intent is resolved (threshold reached, quorum reached, etc), it can be executed. 
///      This returns an Executable hot potato constructed from certain fields of the validated Intent. 
///      It is directly passed into action functions to enforce account approval for an action to be executed.
///   3. The module that created the intent must destroy all of the actions and the Executable after execution 
///      by passing the same witness that was used for instantiation. 
///      This prevents the actions or the intent to be stored instead of executed.
/// 
/// Dependencies can create and manage dynamic fields for an account.
/// They should use custom types as keys to enable access only via the accessors defined.
/// 
/// Functions related to authentication, intent resolution, state of intents and config for an account type 
/// must be called from the module that defines the config of the account.
/// They necessitate a config_witness to ensure the caller is a dependency of the account.
/// 
/// The rest of the functions manipulating the common state of accounts are only called within this package.

module account_protocol::account;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    transfer::Receiving,
    clock::Clock, 
    dynamic_field as df,
    dynamic_object_field as dof,
    package,
};
use account_protocol::{
    metadata::{Self, Metadata},
    deps::{Self, Deps},
    version_witness::{Self, VersionWitness},
    intents::{Self, Intents, Intent, Expired, Params},
    executable::{Self, Executable},
    version,
};

// === Errors ===

const ECantBeRemovedYet: u64 = 1;
const EHasntExpired: u64 = 2;
const ECantBeExecutedYet: u64 = 3;
const EWrongAccount: u64 = 4;
const ENotCalledFromConfigModule: u64 = 5;
const EActionsRemaining: u64 = 6;
const EManagedDataAlreadyExists: u64 = 7;
const EManagedDataDoesntExist: u64 = 8;
const EManagedAssetAlreadyExists: u64 = 9;
const EManagedAssetDoesntExist: u64 = 10;

// === Structs ===

public struct ACCOUNT has drop {}

/// Shared multisig Account object.
public struct Account<Config> has key, store {
    id: UID,
    // arbitrary data that can be proposed and added by members
    // first field is a human readable name to differentiate the multisig accounts
    metadata: Metadata,
    // ids and versions of the packages this account is using
    // idx 0: account_protocol, idx 1: account_actions optionally
    deps: Deps,
    // open intents, key should be a unique descriptive name
    intents: Intents,
    // config can be anything (e.g. Multisig, coin-based DAO, etc.)
    config: Config,
}

/// Protected type ensuring provenance, authenticate an address to an account.
public struct Auth {
    // address of the account that created the auth
    account_addr: address,
}

//**************************************************************************************************//
// Public functions                                                                                //
//**************************************************************************************************//

fun init(otw: ACCOUNT, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx); // to create Display objects in the future
}

/// Verifies all actions have been processed and destroys the executable.
/// Called to complete the intent execution.
public fun confirm_execution<Config, Outcome: drop + store>(
    account: &mut Account<Config>, 
    executable: Executable<Outcome>,
) {
    let actions_length = executable.intent().actions().length();
    assert!(executable.action_idx() == actions_length, EActionsRemaining);
    
    let intent = executable.destroy();
    intent.assert_is_account(account.addr());
    
    account.intents.add_intent(intent);
}

/// Destroys an intent if it has no remaining execution.
/// Expired needs to be emptied by deleting each action in the bag within their own module.
public fun destroy_empty_intent<Config, Outcome: store + drop>(
    account: &mut Account<Config>, 
    key: String, 
): Expired {
    assert!(account.intents.get<Outcome>(key).execution_times().is_empty(), ECantBeRemovedYet);
    account.intents.destroy_intent<Outcome>(key)
}

/// Destroys an intent if it has expired.
/// Expired needs to be emptied by deleting each action in the bag within their own module.
public fun delete_expired_intent<Config, Outcome: store + drop>(
    account: &mut Account<Config>, 
    key: String, 
    clock: &Clock,
): Expired {
    assert!(clock.timestamp_ms() >= account.intents.get<Outcome>(key).expiration_time(), EHasntExpired);
    account.intents.destroy_intent<Outcome>(key)
}

/// Helper function to transfer an object to the account.
public fun keep<Config, T: key + store>(account: &Account<Config>, obj: T) {
    transfer::public_transfer(obj, account.addr());
}

/// Unpacks and verifies the Auth matches the account.
public fun verify<Config>(
    account: &Account<Config>,
    auth: Auth,
) {
    let Auth { account_addr } = auth;

    assert!(account.addr() == account_addr, EWrongAccount);
}

//**************************************************************************************************//
// Deps-only functions                                                                              //
//**************************************************************************************************//

/// The following functions are used to compose intents in external modules and packages.
/// 
/// The proper instantiation and execution of an intent is ensured by an intent witness.
/// This is a drop only type defined in the intent module preventing other modules to misuse the intent.
/// 
/// Additionally, these functions require a version witness which is a protected type for the protocol. 
/// It is checked against the dependencies of the account to ensure the package being called is authorized.
/// VersionWitness is a wrapper around a type defined in the version of the package being called.
/// It behaves like a witness but it is usable in the entire package instead of in a single module.

/// Creates a new intent. Can only be called from a dependency of the account.
public fun create_intent<Config, Outcome: store, IW: drop>(
    account: &Account<Config>,
    params: Params,
    outcome: Outcome, // resolution settings
    managed_name: String, // managed struct/object name for the role
    version_witness: VersionWitness, // proof of the package address that creates the intent
    intent_witness: IW, // intent witness
    ctx: &mut TxContext
): Intent<Outcome> {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness); 

    params.new_intent(
        outcome,
        managed_name,
        account.addr(),
        intent_witness,
        ctx
    )
}

/// Adds an intent to the account. Can only be called from a dependency of the account.
public fun insert_intent<Config, Outcome: store, IW: drop>(
    account: &mut Account<Config>, 
    intent: Intent<Outcome>, 
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    // ensures the right account is passed
    intent.assert_is_account(account.addr());
    // ensures the intent is created by the same package that creates the action
    intent.assert_is_witness(intent_witness);

    account.intents.add_intent(intent);
}

/// Managed data and assets:
/// Data structs and Assets objects attached as dynamic fields to the account object.
/// They are separated to improve objects discoverability on frontends and indexers.
/// Keys must be custom types defined in the same module where the function is implemented.

/// Adds a managed data struct to the account.
public fun add_managed_data<Config, Key: copy + drop + store, Data: store>(
    account: &mut Account<Config>, 
    key: Key, 
    data: Data,
    version_witness: VersionWitness,
) {
    assert!(!has_managed_data(account, key), EManagedDataAlreadyExists);
    account.deps().check(version_witness);
    df::add(&mut account.id, key, data);
}

/// Checks if a managed data struct exists in the account.
public fun has_managed_data<Config, Key: copy + drop + store>(
    account: &Account<Config>, 
    key: Key, 
): bool {
    df::exists_(&account.id, key)
}

/// Borrows a managed data struct from the account.
public fun borrow_managed_data<Config, Key: copy + drop + store, Data: store>(
    account: &Account<Config>,
    key: Key, 
    version_witness: VersionWitness,
): &Data {
    assert!(has_managed_data(account, key), EManagedDataDoesntExist);
    account.deps().check(version_witness);
    df::borrow(&account.id, key)
}

/// Borrows a managed data struct mutably from the account.
public fun borrow_managed_data_mut<Config, Key: copy + drop + store, Data: store>(
    account: &mut Account<Config>, 
    key: Key, 
    version_witness: VersionWitness,
): &mut Data {
    assert!(has_managed_data(account, key), EManagedDataDoesntExist);
    account.deps().check(version_witness);
    df::borrow_mut(&mut account.id, key)
}

/// Removes a managed data struct from the account.
public fun remove_managed_data<Config, Key: copy + drop + store, A: store>(
    account: &mut Account<Config>, 
    key: Key, 
    version_witness: VersionWitness,
): A {
    assert!(has_managed_data(account, key), EManagedDataDoesntExist);
    account.deps().check(version_witness);
    df::remove(&mut account.id, key)
}

/// Adds a managed object to the account.
public fun add_managed_asset<Config, Key: copy + drop + store, Asset: key + store>(
    account: &mut Account<Config>, 
    key: Key, 
    asset: Asset,
    version_witness: VersionWitness,
) {
    assert!(!has_managed_asset(account, key), EManagedAssetAlreadyExists);
    account.deps().check(version_witness);
    dof::add(&mut account.id, key, asset);
}

/// Checks if a managed object exists in the account.
public fun has_managed_asset<Config, Key: copy + drop + store>(
    account: &Account<Config>, 
    key: Key, 
): bool {
    dof::exists_(&account.id, key)
}

/// Borrows a managed object from the account.
public fun borrow_managed_asset<Config, Key: copy + drop + store, Asset: key + store>(
    account: &Account<Config>,
    key: Key, 
    version_witness: VersionWitness,
): &Asset {
    assert!(has_managed_asset(account, key), EManagedAssetDoesntExist);
    account.deps().check(version_witness);
    dof::borrow(&account.id, key)
}

/// Borrows a managed object mutably from the account.
public fun borrow_managed_asset_mut<Config, Key: copy + drop + store, Asset: key + store>(
    account: &mut Account<Config>, 
    key: Key, 
    version_witness: VersionWitness,
): &mut Asset {
    assert!(has_managed_asset(account, key), EManagedAssetDoesntExist);
    account.deps().check(version_witness);
    dof::borrow_mut(&mut account.id, key)
}

/// Removes a managed object from the account.
public fun remove_managed_asset<Config, Key: copy + drop + store, Asset: key + store>(
    account: &mut Account<Config>, 
    key: Key, 
    version_witness: VersionWitness,
): Asset {
    assert!(has_managed_asset(account, key), EManagedAssetDoesntExist);
    account.deps().check(version_witness);
    dof::remove(&mut account.id, key)
}

//**************************************************************************************************//
// Config-only functions                                                                            //
//**************************************************************************************************//

/// The following functions are used to define account and intent behavior for a specific account type/config.
/// 
/// They must be implemented in the module that defines the config of the account, which must be a dependency of the account.
/// We provide higher level macros to facilitate the implementation of these functions.

/// Creates a new account with default dependencies. Can only be called from the config module.
public fun new<Config, CW: drop>(
    config: Config, 
    deps: Deps,
    version_witness: VersionWitness,
    config_witness: CW,
    ctx: &mut TxContext
): Account<Config> {
    let account = Account<Config> { 
        id: object::new(ctx),
        metadata: metadata::empty(),
        deps,
        intents: intents::empty(ctx),
        config,
    };

    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    account 
}

/// Returns an Auth object that can be used to call gated functions. Can only be called from the config module.
public fun new_auth<Config, CW: drop>(
    account: &Account<Config>,
    version_witness: VersionWitness,
    config_witness: CW,
): Auth {
    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    Auth { account_addr: account.addr() }
}

/// Returns a tuple of the outcome that must be validated and the executable. Can only be called from the config module.
public fun create_executable<Config, Outcome: store + copy, CW: drop>(
    account: &mut Account<Config>,
    key: String, 
    clock: &Clock,
    version_witness: VersionWitness,
    config_witness: CW,
): (Outcome, Executable<Outcome>) {
    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    let mut intent = account.intents.remove_intent<Outcome>(key);
    let time = intent.pop_front_execution_time();
    assert!(clock.timestamp_ms() >= time, ECantBeExecutedYet);

    (
        *intent.outcome(),
        executable::new(intent) 
    )
}

/// Returns a mutable reference to the intents of the account. Can only be called from the config module.
public fun intents_mut<Config, CW: drop>(
    account: &mut Account<Config>, 
    version_witness: VersionWitness,
    config_witness: CW,
): &mut Intents {
    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    &mut account.intents
}

/// Returns a mutable reference to the config of the account. Can only be called from the config module.
public fun config_mut<Config, CW: drop>(
    account: &mut Account<Config>, 
    version_witness: VersionWitness,
    config_witness: CW,
): &mut Config {
    account.deps().check(version_witness);
    account.assert_is_config_module(config_witness);

    &mut account.config
}

//**************************************************************************************************//
// View functions                                                                                   //
//**************************************************************************************************//

/// Returns the address of the account.
public fun addr<Config>(account: &Account<Config>): address {
    account.id.uid_to_inner().id_to_address()
}

/// Returns the metadata of the account.
public fun metadata<Config>(account: &Account<Config>): &Metadata {
    &account.metadata
}

/// Returns the dependencies of the account.
public fun deps<Config>(account: &Account<Config>): &Deps {
    &account.deps
}

/// Returns the intents of the account.
public fun intents<Config>(account: &Account<Config>): &Intents {
    &account.intents
}

/// Returns the config of the account.
public fun config<Config>(account: &Account<Config>): &Config {
    &account.config
}

//**************************************************************************************************//
// Package functions                                                                                //
//**************************************************************************************************//

/// Returns a mutable reference to the metadata of the account.
public(package) fun metadata_mut<Config>(
    account: &mut Account<Config>, 
    version_witness: VersionWitness,
): &mut Metadata {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    &mut account.metadata
}

/// Returns a mutable reference to the dependencies of the account.
public(package) fun deps_mut<Config>(
    account: &mut Account<Config>, 
    version_witness: VersionWitness,
): &mut Deps {
    // ensures the package address is a dependency for this account
    account.deps().check(version_witness);
    &mut account.deps
}

/// Receives an object from an account, only used in owned action lib module.
public(package) fun receive<Config, T: key + store>(
    account: &mut Account<Config>, 
    receiving: Receiving<T>,
): T {
    transfer::public_receive(&mut account.id, receiving)
}

/// Locks an object in the account, preventing it to be used in another intent.
public(package) fun lock_object<Config>(
    account: &mut Account<Config>, 
    id: ID,
) {
    account.intents.lock(id);
}

/// Unlocks an object in the account, allowing it to be used in another intent.
public(package) fun unlock_object<Config>(
    account: &mut Account<Config>, 
    id: ID,
) {
    account.intents.unlock(id);
}

/// Asserts that the function is called from the module defining the config of the account.
public(package) fun assert_is_config_module<Config, CW: drop>(
    _account: &Account<Config>, 
    _config_witness: CW
) {
    let account_type = type_name::get<Config>();
    let witness_type = type_name::get<CW>();
    assert!(
        account_type.get_address() == witness_type.get_address() &&
        account_type.get_module() == witness_type.get_module(),
        ENotCalledFromConfigModule
    );
}

//**************************************************************************************************//
// Tests                                                                                            //
//**************************************************************************************************//

// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ACCOUNT {}, ctx);
}

#[test_only]
public struct Witness() has drop;

#[test_only]
public fun not_config_witness(): Witness {
    Witness()
}

// === Unit Tests ===

#[test_only]
use sui::test_utils::{assert_eq, destroy};
use account_extensions::extensions;

#[test_only]
public struct TestConfig has copy, drop, store {}
#[test_only]
public struct TestWitness() has drop;
#[test_only]
public struct WrongWitness() has drop;
#[test_only]
public struct TestKey has copy, drop, store {}
#[test_only]
public struct TestData has copy, drop, store {
    value: u64
}
#[test_only]
public struct TestAsset has key, store {
    id: UID
}

#[test]
fun test_addr() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let account_addr = addr(&account);
    
    assert_eq(account_addr, object::id(&account).to_address());
    destroy(account);
}

#[test]
fun test_verify_auth() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let auth = Auth { account_addr: account.addr() };
    
    // Should not abort
    verify(&account, auth);
    destroy(account);
}

#[test, expected_failure(abort_code = EWrongAccount)]
fun test_verify_auth_wrong_account() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let auth = Auth { account_addr: @0xBAD };
    
    verify(&account, auth);
    destroy(account);
}

#[test]
fun test_managed_data_flow() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let mut account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    let data = TestData { value: 42 };
    
    // Test add
    add_managed_data(&mut account, key, data, version::current());
    assert!(has_managed_data(&account, key));
    
    // Test borrow
    let borrowed_data = borrow_managed_data(&account, key, version::current());
    assert_eq(*borrowed_data, data);
    
    // Test borrow_mut
    let borrowed_mut_data = borrow_managed_data_mut(&mut account, key, version::current());
    assert_eq(*borrowed_mut_data, data);
    
    // Test remove
    let removed_data = remove_managed_data(&mut account, key, version::current());
    assert_eq(removed_data, data);
    assert!(!has_managed_data(&account, key));
    destroy(account);
}

#[test, expected_failure(abort_code = EManagedDataAlreadyExists)]
fun test_add_managed_data_already_exists() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let mut account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    let data1 = TestData { value: 42 };
    let data2 = TestData { value: 100 };
    
    add_managed_data(&mut account, key, data1, version::current());
    add_managed_data(&mut account, key, data2, version::current());
    destroy(account);
}

#[test, expected_failure(abort_code = EManagedDataDoesntExist)]
fun test_borrow_managed_data_doesnt_exist() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    
    borrow_managed_data<_, TestKey, TestData>(&account, key, version::current());
    destroy(account);
}

#[test, expected_failure(abort_code = EManagedDataDoesntExist)]
fun test_borrow_managed_data_mut_doesnt_exist() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let mut account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    
    borrow_managed_data_mut<_, TestKey, TestData>(&mut account, key, version::current());
    destroy(account);
}

#[test, expected_failure(abort_code = EManagedDataDoesntExist)]
fun test_remove_managed_data_doesnt_exist() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let mut account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    
    remove_managed_data<_, TestKey, TestData>(&mut account, key, version::current());
    destroy(account);
}

#[test]
fun test_managed_asset_flow() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let mut account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    let asset = TestAsset { id: object::new(ctx) };
    let asset_id = object::id(&asset);
    
    // Test add
    add_managed_asset(&mut account, key, asset, version::current());
    assert!(has_managed_asset(&account, key), 0);
    
    // Test borrow
    let borrowed_asset = borrow_managed_asset<_, TestKey, TestAsset>(&account, key, version::current());
    assert_eq(object::id(borrowed_asset), asset_id);
    
    // Test remove
    let removed_asset = remove_managed_asset<_, TestKey, TestAsset>(&mut account, key, version::current());
    assert_eq(object::id(&removed_asset), asset_id);
    assert!(!has_managed_asset(&account, key));
    destroy(account);
    destroy(removed_asset);
}

#[test]
fun test_has_managed_data_false() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    
    assert!(!has_managed_data(&account, key));
    destroy(account);
}

#[test]
fun test_has_managed_asset_false() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    
    assert!(!has_managed_asset(&account, key));
    destroy(account);
}

#[test, expected_failure(abort_code = EManagedAssetAlreadyExists)]
fun test_add_managed_asset_already_exists() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let mut account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    let asset1 = TestAsset { id: object::new(ctx) };
    let asset2 = TestAsset { id: object::new(ctx) };
    
    add_managed_asset(&mut account, key, asset1, version::current());
    add_managed_asset(&mut account, key, asset2, version::current());
    destroy(account);
}

#[test, expected_failure(abort_code = EManagedAssetDoesntExist)]
fun test_borrow_managed_asset_doesnt_exist() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    
    borrow_managed_asset<_, TestKey, TestAsset>(&account, key, version::current());
    destroy(account);
}

#[test, expected_failure(abort_code = EManagedAssetDoesntExist)]
fun test_borrow_managed_asset_mut_doesnt_exist() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let mut account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    
    borrow_managed_asset_mut<_, TestKey, TestAsset>(&mut account, key, version::current());
    destroy(account);
}

#[test, expected_failure(abort_code = EManagedAssetDoesntExist)]
fun test_remove_managed_asset_doesnt_exist() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let mut account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let key = TestKey {};
    
    let removed_asset = remove_managed_asset<_, TestKey, TestAsset>(&mut account, key, version::current());
    destroy(removed_asset);
    destroy(account);
}

#[test]
fun test_new_auth() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    let auth = new_auth(&account, version::current(), TestWitness());
    
    assert_eq(auth.account_addr, account.addr());
    destroy(account);
    destroy(auth);
}

#[test]
fun test_metadata_access() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    
    // Should not abort - just testing access
    assert_eq(metadata(&account).size(), 0);
    destroy(account);
}

#[test]
fun test_config_access() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    
    // Should not abort - just testing access
    config(&account);
    destroy(account);
}

#[test]
fun test_assert_is_config_module_correct_witness() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    
    // Should not abort
    assert_is_config_module(&account, TestWitness());
    destroy(account);
}

#[test, expected_failure(abort_code = ENotCalledFromConfigModule)]
fun test_assert_config_module_wrong_witness_package_address() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    assert_is_config_module(&account, extensions::witness());
    destroy(account);
}

#[test, expected_failure(abort_code = ENotCalledFromConfigModule)]
fun test_assert_config_module_wrong_witness_module() {
    let ctx = &mut tx_context::dummy();
    let deps = deps::new_for_testing();
    
    let account = new(TestConfig {}, deps, version::current(), TestWitness(), ctx);
    assert_is_config_module(&account, version::witness());
    destroy(account);
}