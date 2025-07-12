#[test_only]
module account_protocol::user_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    user::{Self, Registry, User, Invite},
    deps,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;
const ALICE: address = @0xA11CE;

// === Structs ===

public struct Witness() has drop;
public struct DummyIntent() has drop;

public struct DummyConfig has copy, drop, store {}

public struct AccountConfig1 has copy, drop, store {}
public struct AccountConfig2 has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Registry, Extensions) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    user::init_for_testing(scenario.ctx());
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let registry = scenario.take_shared<Registry>();

    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    
    destroy(cap);
    (scenario, registry, extensions)
}

fun end(scenario: Scenario, registry: Registry, extensions: Extensions) {
    destroy(extensions);
    destroy(registry);
    ts::end(scenario);
}

fun create_account(extensions: &Extensions, ctx: &mut TxContext): Account<DummyConfig> {
    let deps = deps::new_latest_extensions(extensions, vector[b"AccountProtocol".to_string()]);
    account::new(DummyConfig {}, deps, version::current(), Witness(), ctx)
}

fun create_account_with_config<T: drop>(extensions: &Extensions, config: T, ctx: &mut TxContext): Account<T> {
    let deps = deps::new_latest_extensions(extensions, vector[b"AccountProtocol".to_string()]);
    account::new(config, deps, version::current(), Witness(), ctx)
}

// === Tests ===

#[test]
fun test_user_flow() {
    let (mut scenario, mut registry, extensions) = start();

    let mut user = user::new(scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    let account1 = create_account(&extensions, scenario.ctx());
    let account2 = create_account(&extensions, scenario.ctx());
    let account3 = create_account(&extensions, scenario.ctx());

    user.add_account(&account1, Witness());
    user.add_account(&account2, Witness());
    user.add_account(&account3, Witness());
    assert!(user.all_ids() == vector[account1.addr(), account2.addr(), account3.addr()]);
    assert!(user.ids_for_type<DummyConfig>() == vector[account1.addr(), account2.addr(), account3.addr()]);

    user.remove_account(&account1, Witness());
    user.remove_account(&account2, Witness());
    user.remove_account(&account3, Witness());
    assert!(user.all_ids() == vector[]);

    registry.transfer(user, OWNER, scenario.ctx());
    assert!(registry.users().length() == 1);
    assert!(registry.users().contains(OWNER));

    scenario.next_tx(OWNER);
    let user = scenario.take_from_sender<User>();
    registry.destroy(user, scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    destroy(account1);
    destroy(account2);
    destroy(account3);
    end(scenario, registry, extensions);
}

#[test]
fun test_user_add_multiple_accounts_of_different_types() {
    let (mut scenario, registry, extensions) = start();

    let mut user = user::new(scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    let account1 = create_account(&extensions, scenario.ctx());
    let account2 = create_account(&extensions, scenario.ctx());
    let account3 = create_account_with_config(&extensions, AccountConfig1 {}, scenario.ctx());
    let account4 = create_account_with_config(&extensions, AccountConfig2 {}, scenario.ctx());

    user.add_account(&account1, Witness());
    user.add_account(&account2, Witness());
    user.add_account(&account3, Witness());
    user.add_account(&account4, Witness());

    assert!(user.all_ids() == vector[account4.addr(), account3. addr(), account1.addr(), account2.addr()]);
    assert!(user.ids_for_type<DummyConfig>() == vector[account1.addr(), account2.addr()]);
    assert!(user.ids_for_type<AccountConfig1>() == vector[account3.addr()]);
    assert!(user.ids_for_type<AccountConfig2>() == vector[account4.addr()]);

    user.remove_account(&account1, Witness());
    user.remove_account(&account2, Witness());
    user.remove_account(&account3, Witness());
    user.remove_account(&account4, Witness());
    assert!(user.all_ids() == vector[]);

    destroy(account1);
    destroy(account2);
    destroy(account3);
    destroy(account4);
    destroy(user);
    end(scenario, registry, extensions);
}

#[test]
fun test_send_invites() {
    let (mut scenario, registry, extensions) = start();

    let mut user = user::new(scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    let account1 = create_account(&extensions, scenario.ctx());
    let account2 = create_account(&extensions, scenario.ctx());
    let account3 = create_account_with_config(&extensions, AccountConfig1 {}, scenario.ctx());
    let account4 = create_account_with_config(&extensions, AccountConfig2 {}, scenario.ctx());

    user::send_invite(&account1, OWNER, Witness(), scenario.ctx());
    scenario.next_tx(OWNER);
    let invite1 = scenario.take_from_sender<Invite>();
    user::send_invite(&account2, OWNER, Witness(), scenario.ctx());
    scenario.next_tx(OWNER);
    let invite2 = scenario.take_from_sender<Invite>();
    user::send_invite(&account3, OWNER, Witness(), scenario.ctx());
    scenario.next_tx(OWNER);
    let invite3 = scenario.take_from_sender<Invite>();
    user::send_invite(&account4, OWNER, Witness(), scenario.ctx());
    scenario.next_tx(OWNER);
    let invite4 = scenario.take_from_sender<Invite>();

    user.accept_invite(invite1);
    assert!(user.ids_for_type<DummyConfig>() == vector[account1.addr()]);
    user.accept_invite(invite2);
    assert!(user.ids_for_type<DummyConfig>() == vector[account1.addr(), account2.addr()]);
    user.accept_invite(invite3);
    assert!(user.ids_for_type<AccountConfig1>() == vector[account3.addr()]);
    user.accept_invite(invite4);
    assert!(user.ids_for_type<AccountConfig2>() == vector[account4.addr()]);

    destroy(account1);
    destroy(account2);
    destroy(account3);
    destroy(account4);
    destroy(user);
    end(scenario, registry, extensions);
}

#[test, expected_failure(abort_code = user::EAccountAlreadyRegistered)]
fun test_error_add_already_existing_account() {
    let (mut scenario, registry, extensions) = start();
    let mut user = user::new(scenario.ctx());

    let account = create_account(&extensions, scenario.ctx());
    user.add_account(&account, Witness());
    user.add_account(&account, Witness());

    destroy(account);
    destroy(user);
    end(scenario, registry, extensions);
}

#[test, expected_failure(abort_code = user::EAccountTypeDoesntExist)]
fun test_error_remove_empty_account_type() {
    let (mut scenario, registry, extensions) = start();
    let account = create_account(&extensions, scenario.ctx());

    let mut user = user::new(scenario.ctx());
    user.remove_account(&account, Witness());

    destroy(user);
    destroy(account);   
    end(scenario, registry, extensions);
}

#[test, expected_failure(abort_code = user::EAccountNotFound)]
fun test_error_remove_wrong_account() {
    let (mut scenario, registry, extensions) = start();

    let account1 = create_account(&extensions, scenario.ctx());
    let account2 = create_account(&extensions, scenario.ctx());

    let mut user = user::new(scenario.ctx());
    user.add_account(&account1, Witness());
    user.remove_account(&account2, Witness());

    destroy(user);
    destroy(account1);
    destroy(account2);
    end(scenario, registry, extensions);
}
