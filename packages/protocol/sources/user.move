/// Users have a non-transferable User account object used to track Accounts in which they are a member.
/// Each account type can define a way to send on-chain invites to Users.
/// Invited users can accept or refuse the invite, to add the Account id to their User account or not.
/// Alternatively, Account interfaces can define rules allowing users to join an Account without invite.
/// This avoid the need for an indexer as all data can be easily found on-chain.

module account_protocol::user;

// === Imports ===

use std::{
    string::String,
    type_name,
};
use sui::{
    vec_map::{Self, VecMap},
    table::{Self, Table},
};
use account_protocol::account::Account;

// === Errors ===

const ENotEmpty: u64 = 0;
const EAlreadyHasUser: u64 = 1;
const EAccountNotFound: u64 = 2;
const EAccountTypeDoesntExist: u64 = 3;
const EWrongUserId: u64 = 4;
const EAccountAlreadyRegistered: u64 = 5;
const EWrongNumberOfAccounts: u64 = 6;
const ENoAccountsToReorder: u64 = 7;

// === Struct ===

/// Shared object enforcing one account maximum per user
public struct Registry has key {
    id: UID,
    // address to User ID mapping
    users: Table<address, ID>,
}

/// Non-transferable user account for tracking Accounts
public struct User has key {
    id: UID,
    // account type to list of accounts that the user has joined
    accounts: VecMap<String, vector<address>>,
}

/// Invite object issued by an Account to a user
public struct Invite has key { 
    id: UID, 
    // Account that issued the invite
    account_addr: address,
    // Account type
    account_type: String,
}

// === Public functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(Registry {
        id: object::new(ctx),
        users: table::new(ctx),
    });
}

/// Creates a soulbound User account (1 per address)
public fun new(ctx: &mut TxContext): User {
    User {
        id: object::new(ctx),
        accounts: vec_map::empty(),
    }
}

/// Can transfer the User object only if the other address has no User object yet
public fun transfer(registry: &mut Registry, user: User, recipient: address, ctx: &mut TxContext) {
    assert!(!registry.users.contains(recipient), EAlreadyHasUser);
    // if the sender is not in the registry, then the User has been just created
    if (registry.users.contains(ctx.sender())) {
        let id = registry.users.remove(ctx.sender());
        assert!(id == object::id(&user), EWrongUserId); // should never throw
    };

    registry.users.add(recipient, object::id(&user));
    transfer::transfer(user, recipient);
}

/// Must remove all Accounts before, for consistency
public fun destroy(registry: &mut Registry, user: User, ctx: &mut TxContext) {
    let User { id, accounts, .. } = user;
    assert!(accounts.is_empty(), ENotEmpty);

    id.delete();
    registry.users.remove(ctx.sender());
}

/// Invited user can register the Account in his User account
public fun accept_invite(user: &mut User, invite: Invite) {
    let Invite { id, account_addr, account_type } = invite;
    id.delete();
    
    if (user.accounts.contains(&account_type)) {
        assert!(!user.accounts[&account_type].contains(&account_addr), EAccountAlreadyRegistered);
        user.accounts.get_mut(&account_type).push_back(account_addr);
    } else {
        user.accounts.insert(account_type, vector<address>[account_addr]);
    }
}

/// Deletes the invite object
public fun refuse_invite(invite: Invite) {
    let Invite { id, .. } = invite;
    id.delete();
}

public fun reorder_accounts<Config>(user: &mut User, addrs: vector<address>) {
    let account_type = type_name::get<Config>().into_string().to_string();
    assert!(user.accounts.contains(&account_type), ENoAccountsToReorder);

    let accounts = user.accounts.get_mut(&account_type);

    assert!(accounts.length() == addrs.length(), EWrongNumberOfAccounts);
    assert!(!accounts.is_empty(), ENoAccountsToReorder);

    let mut new_order = vector[];
    addrs.do!(|addr| {
        let (exists, idx) = accounts.index_of(&addr);
        assert!(exists, EAccountNotFound);
        accounts.swap_remove(idx);
        new_order.push_back(addr);
    });

    *accounts = new_order;
}
// === Config-only functions ===

public fun add_account<Config, CW: drop>(
    user: &mut User, 
    account: &Account<Config>, 
    config_witness: CW,
) {
    account.assert_is_config_module(config_witness);
    let account_type = type_name::get<Config>().into_string().to_string();

    if (user.accounts.contains(&account_type)) {
        assert!(!user.accounts[&account_type].contains(&account.addr()), EAccountAlreadyRegistered);
        user.accounts.get_mut(&account_type).push_back(account.addr());
    } else {
        user.accounts.insert(account_type, vector<address>[account.addr()]);
    }
}

public fun remove_account<Config, CW: drop>(
    user: &mut User, 
    account: &Account<Config>, 
    config_witness: CW,
) {
    account.assert_is_config_module(config_witness);
    let account_type = type_name::get<Config>().into_string().to_string();

    assert!(user.accounts.contains(&account_type), EAccountTypeDoesntExist);
    let (exists, idx) = user.accounts[&account_type].index_of(&account.addr());
    
    assert!(exists, EAccountNotFound);
    user.accounts.get_mut(&account_type).swap_remove(idx);

    if (user.accounts[&account_type].is_empty())
        (_, _) = user.accounts.remove(&account_type);
}

/// Invites can be sent by an Account member (upon Account creation for instance)
public fun send_invite<Config, CW: drop>(
    account: &Account<Config>, 
    recipient: address, 
    config_witness: CW,
    ctx: &mut TxContext,
) {
    account.assert_is_config_module(config_witness);
    let account_type = type_name::get<Config>().into_string().to_string();

    transfer::transfer(Invite { 
        id: object::new(ctx), 
        account_addr: account.addr(),
        account_type,
    }, recipient);
}

// === View functions ===    

public fun users(registry: &Registry): &Table<address, ID> {
    &registry.users
}

public fun ids_for_type<Config>(user: &User): vector<address> {
    let account_type = type_name::get<Config>().into_string().to_string();
    user.accounts[&account_type]
}

public fun all_ids(user: &User): vector<address> {
    let mut map = user.accounts;
    let mut ids = vector<address>[];

    while (!map.is_empty()) {
        let (_, vec) = map.pop();
        ids.append(vec);
    };

    ids
}

//**************************************************************************************************//
// Tests                                                                                            //
//**************************************************************************************************//

// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun registry_for_testing(ctx: &mut TxContext): Registry {
    Registry {
        id: object::new(ctx),
        users: table::new(ctx),
    }
}

#[test_only]
public fun add_account_for_testing<Config>(
    user: &mut User,
    account_addr: address,
) {
    let account_type = type_name::get<Config>().into_string().to_string();
    if (user.accounts.contains(&account_type)) {
        assert!(!user.accounts[&account_type].contains(&account_addr), EAccountAlreadyRegistered);
        user.accounts.get_mut(&account_type).push_back(account_addr);
    } else {
        user.accounts.insert(account_type, vector[account_addr]);
    };
}

// === Unit Tests ===

#[test_only]
use sui::test_scenario as ts;
#[test_only]
use sui::test_utils as tu;

#[test_only]
public struct DummyConfig has copy, drop, store {}
#[test_only]
public struct DummyConfig2 has copy, drop, store {}

#[test]
fun test_transfer_user_recipient() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut registry = registry_for_testing(scenario.ctx());
    let user = new(scenario.ctx());

    transfer(&mut registry, user, @0xA11CE, scenario.ctx());
    scenario.next_tx(@0xA11CE);

    let user = ts::take_from_sender<User>(&scenario);
    let user_id = object::id(&user);

    assert!(registry.users.contains(@0xA11CE));
    assert!(registry.users.borrow(@0xA11CE) == user_id);

    tu::destroy(user);
    tu::destroy(registry);
    ts::end(scenario);
}

#[test]
fun test_destroy_user() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut registry = registry_for_testing(scenario.ctx());
    let user = new(scenario.ctx());

    transfer(&mut registry, user, @0xA11CE, scenario.ctx());
    scenario.next_tx(@0xA11CE);

    let user = ts::take_from_sender<User>(&scenario);
    destroy(&mut registry, user, scenario.ctx());

    assert!(!registry.users.contains(@0xA11CE));
    tu::destroy(registry);
    ts::end(scenario);
}

#[test]
fun test_accept_invite() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut user = new(scenario.ctx());

    let invite = Invite {
        id: object::new(scenario.ctx()),
        account_addr: @0xACC,
        account_type: b"0x0::config::Config".to_string(),
    };

    accept_invite(&mut user, invite);
    assert!(user.accounts.contains(&b"0x0::config::Config".to_string()));
    assert!(user.accounts[&b"0x0::config::Config".to_string()].contains(&@0xACC));

    tu::destroy(user);
    ts::end(scenario);
}

#[test]
fun test_refuse_invite() {
    let mut scenario = ts::begin(@0xCAFE);
    let user = new(scenario.ctx());

    let invite = Invite {
        id: object::new(scenario.ctx()),
        account_addr: @0xACC,
        account_type: b"0x0::config::Config".to_string(),
    };

    refuse_invite(invite);
    assert!(!user.accounts.contains(&b"0x0::config::Config".to_string()));

    tu::destroy(user);
    ts::end(scenario);
}

#[test]
fun test_reorder_accounts() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut user = new(scenario.ctx());
    
    user.add_account_for_testing<DummyConfig>(@0x1);
    user.add_account_for_testing<DummyConfig>(@0x2);
    user.add_account_for_testing<DummyConfig>(@0x3);
    let key = type_name::get<DummyConfig>().into_string().to_string();
    assert!(user.accounts.get(&key) == vector[@0x1, @0x2, @0x3]);

    user.reorder_accounts<DummyConfig>(vector[@0x2, @0x3, @0x1]);
    assert!(user.accounts.get(&key) == vector[@0x2, @0x3, @0x1]);

    tu::destroy(user);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EAlreadyHasUser)]
fun test_error_transfer_to_existing_user() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut registry = registry_for_testing(scenario.ctx());

    registry.transfer(new(scenario.ctx()), @0xCAFE, scenario.ctx());
    registry.transfer(new(scenario.ctx()), @0xCAFE, scenario.ctx());

    tu::destroy(registry);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EWrongUserId)]
fun test_error_transfer_wrong_user_object() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut registry = registry_for_testing(scenario.ctx());

    registry.transfer(new(scenario.ctx()), @0xCAFE, scenario.ctx());
    // OWNER transfers wrong user object to ALICE
    registry.transfer(new(scenario.ctx()), @0xA11CE, scenario.ctx());

    tu::destroy(registry);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = ENotEmpty)]
fun test_error_destroy_non_empty_user() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut registry = registry_for_testing(scenario.ctx());
    let mut user = new(scenario.ctx());

    user.add_account_for_testing<DummyConfig>(@0xACC);
    destroy(&mut registry, user, scenario.ctx());

    tu::destroy(registry);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EAccountAlreadyRegistered)]
fun test_error_add_already_existing_account() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut user = new(scenario.ctx());

    user.add_account_for_testing<DummyConfig>(@0xACC);
    user.add_account_for_testing<DummyConfig>(@0xACC);
    
    tu::destroy(user);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = ENoAccountsToReorder)]
fun test_reorder_accounts_empty() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut user = new(scenario.ctx());

    user.reorder_accounts<DummyConfig>(vector[]);

    tu::destroy(user);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = ENoAccountsToReorder)]
fun test_reorder_accounts_type_empty() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut user = new(scenario.ctx());

    user.add_account_for_testing<DummyConfig>(@0xACC);
    user.reorder_accounts<DummyConfig2>(vector[@0xACC]);

    tu::destroy(user);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EWrongNumberOfAccounts)]
fun test_reorder_accounts_different_length() {
    let mut scenario = ts::begin(@0xCAFE);
    
    let mut user = new(scenario.ctx());
    user.add_account_for_testing<DummyConfig>(@0xACC);
    user.add_account_for_testing<DummyConfig>(@0xACC2);

    user.reorder_accounts<DummyConfig>(vector[@0xACC]);

    tu::destroy(user);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = EAccountNotFound)]
fun test_reorder_accounts_wrong_account() {
    let mut scenario = ts::begin(@0xCAFE);
    let mut user = new(scenario.ctx());
    
    user.add_account_for_testing<DummyConfig>(@0x1);
    user.add_account_for_testing<DummyConfig>(@0x2);

    user.reorder_accounts<DummyConfig>(vector[@0x1, @0x3]);

    tu::destroy(user);
    ts::end(scenario);
}