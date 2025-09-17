#[test_only]
module account_protocol::user_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario as ts,
};
use account_protocol::{
    account::{Self, Account},
    user::{Self, User, Invite},
    deps,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Witness() has drop;
public struct DummyIntent() has drop;

public struct DummyConfig has copy, drop, store {}

public struct AccountConfig1 has copy, drop, store {}
public struct AccountConfig2 has copy, drop, store {}

// === Helpers ===

fun create_account(ctx: &mut TxContext): Account<DummyConfig> {
    let deps = deps::new_for_testing();
    account::new(DummyConfig {}, deps, version::current(), Witness(), ctx)
}

fun create_account_with_config<T: drop>(config: T, ctx: &mut TxContext): Account<T> {
    let deps = deps::new_for_testing();
    account::new(config, deps, version::current(), Witness(), ctx)
}

// === Tests ===

#[test]
fun test_user_flow() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut registry = user::registry_for_testing(scenario.ctx());

    let mut user = user::new(scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    let account1 = create_account(scenario.ctx());
    let account2 = create_account(scenario.ctx());
    let account3 = create_account(scenario.ctx());

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
    destroy(registry);
    ts::end(scenario);
}

#[test]
fun test_user_add_multiple_accounts_of_different_types() {
    let mut scenario = ts::begin(@0xCAFE);
    let registry = user::registry_for_testing(scenario.ctx());

    let mut user = user::new(scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    let account1 = create_account(scenario.ctx());
    let account2 = create_account(scenario.ctx());
    let account3 = create_account_with_config(AccountConfig1 {}, scenario.ctx());
    let account4 = create_account_with_config(AccountConfig2 {}, scenario.ctx());

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
    destroy(registry);
    ts::end(scenario);
}

#[test]
fun test_send_invites() {
    let mut scenario = ts::begin(@0xCAFE);
    let registry = user::registry_for_testing(scenario.ctx());

    let mut user = user::new(scenario.ctx());
    assert!(registry.users().length() == 0);
    assert!(!registry.users().contains(OWNER));

    let account1 = create_account(scenario.ctx());
    let account2 = create_account(scenario.ctx());
    let account3 = create_account_with_config(AccountConfig1 {}, scenario.ctx());
    let account4 = create_account_with_config(AccountConfig2 {}, scenario.ctx());

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
    destroy(registry);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = user::EAccountAlreadyRegistered)]
fun test_error_add_already_existing_account() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut user = user::new(scenario.ctx());

    let account = create_account(scenario.ctx());
    user.add_account(&account, Witness());
    user.add_account(&account, Witness());

    destroy(account);
    destroy(user);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = user::EAccountTypeDoesntExist)]
fun test_error_remove_empty_account_type() {
    let mut scenario = ts::begin(@0xCAFE);
    let account = create_account(scenario.ctx());

    let mut user = user::new(scenario.ctx());
    user.remove_account(&account, Witness());

    destroy(user);
    destroy(account);   
    ts::end(scenario);
}

#[test, expected_failure(abort_code = user::EAccountNotFound)]
fun test_error_remove_wrong_account() {
    let mut scenario = ts::begin(@0xCAFE);

    let account1 = create_account(scenario.ctx());
    let account2 = create_account(scenario.ctx());

    let mut user = user::new(scenario.ctx());
    user.add_account(&account1, Witness());
    user.remove_account(&account2, Witness());

    destroy(user);
    destroy(account1);
    destroy(account2);
    ts::end(scenario);
}
