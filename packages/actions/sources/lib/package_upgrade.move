/// Package managers can lock UpgradeCaps in the account. Caps can't be unlocked, this is to enforce the policies.
/// Any rule can be defined for the upgrade lock. The module provide a timelock rule by default, based on execution time.
/// Upon locking, the user can define an optional timelock corresponding to the minimum delay between an upgrade proposal and its execution.
/// The account can decide to make the policy more restrictive or destroy the Cap, to make the package immutable.

module account_actions::package_upgrade;

// === Imports ===

use std::string::String;
use sui::{
    package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt},
    clock::Clock,
    vec_map::{Self, VecMap},
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Expired, Intent},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_actions::{
    version,
};

// === Error ===

const ELockAlreadyExists: u64 = 0;
const EUpgradeTooEarly: u64 = 1;
const EPackageDoesntExist: u64 = 2;

// === Structs ===

/// Dynamic Object Field key for the UpgradeCap.
public struct UpgradeCapKey(String) has copy, drop, store;
/// Dynamic field key for the UpgradeRules.
public struct UpgradeRulesKey(String) has copy, drop, store;
/// Dynamic field key for the UpgradeIndex.
public struct UpgradeIndexKey() has copy, drop, store;

/// Dynamic field wrapper defining an optional timelock.
public struct UpgradeRules has store {
    // minimum delay between proposal and execution
    delay_ms: u64,
} 

/// Map tracking the latest upgraded package address for a package name.
public struct UpgradeIndex has store {
    // map of package name to address
    packages_info: VecMap<String, address>,
}

/// Action to upgrade a package using a locked UpgradeCap.
public struct UpgradeAction has store {
    // name of the package
    name: String,
    // digest of the package build we want to publish
    digest: vector<u8>,
}
/// Action to commit an upgrade.
public struct CommitAction has store {
    // name of the package
    name: String,
}
/// Action to restrict the policy of a locked UpgradeCap.
public struct RestrictAction has store {
    // name of the package
    name: String,
    // downgrades to this policy
    policy: u8,
}

// === Public Functions ===

/// Attaches the UpgradeCap as a Dynamic Object Field to the account.
public fun lock_cap<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    cap: UpgradeCap,
    name: String, // name of the package
    delay_ms: u64, // minimum delay between proposal and execution
) {
    account.verify(auth);
    assert!(!has_cap(account, name), ELockAlreadyExists);

    if (!account.has_managed_data(UpgradeIndexKey()))
        account.add_managed_data(UpgradeIndexKey(), UpgradeIndex { packages_info: vec_map::empty() }, version::current());

    let upgrade_index_mut: &mut UpgradeIndex = account.borrow_managed_data_mut(UpgradeIndexKey(), version::current());
    upgrade_index_mut.packages_info.insert(name, cap.package().to_address());
    
    account.add_managed_asset(UpgradeCapKey(name), cap, version::current());
    account.add_managed_data(UpgradeRulesKey(name), UpgradeRules { delay_ms }, version::current());
}

/// Returns true if the account has an UpgradeCap for a given package name.
public fun has_cap<Config>(
    account: &Account<Config>, 
    name: String
): bool {
    account.has_managed_asset(UpgradeCapKey(name))
}

/// Returns the address of the package for a given package name.
public fun get_cap_package<Config>(
    account: &Account<Config>, 
    name: String
): address {
    account.borrow_managed_asset<_, _, UpgradeCap>(UpgradeCapKey(name), version::current()).package().to_address()
} 

/// Returns the version of the UpgradeCap for a given package name.
public fun get_cap_version<Config>(
    account: &Account<Config>, 
    name: String
): u64 {
    account.borrow_managed_asset<_, _, UpgradeCap>(UpgradeCapKey(name), version::current()).version()
} 

/// Returns the policy of the UpgradeCap for a given package name.
public fun get_cap_policy<Config>(
    account: &Account<Config>, 
    name: String
): u8 {
    account.borrow_managed_asset<_, _, UpgradeCap>(UpgradeCapKey(name), version::current()).policy()
} 

/// Returns the timelock of the UpgradeRules for a given package name.
public fun get_time_delay<Config>(
    account: &Account<Config>, 
    name: String
): u64 {
    account.borrow_managed_data<_, _, UpgradeRules>(UpgradeRulesKey(name), version::current()).delay_ms
}

/// Returns the map of package names to package addresses.
public fun get_packages_info<Config>(
    account: &Account<Config>
): &VecMap<String, address> {
    &account.borrow_managed_data<_, _, UpgradeIndex>(UpgradeIndexKey(), version::current()).packages_info
}

/// Returns true if the package is managed by the account.
public fun is_package_managed<Config>(
    account: &Account<Config>,
    package_addr: address
): bool {
    if (!account.has_managed_data(UpgradeIndexKey())) return false;
    let index: &UpgradeIndex = account.borrow_managed_data(UpgradeIndexKey(), version::current());
    
    let mut i = 0;
    while (i < index.packages_info.length()) {
        let (_, value) = index.packages_info.get_entry_by_idx(i);
        if (value == package_addr) return true;
        i = i + 1;
    };

    false
}

/// Returns the address of the package for a given package name.
public fun get_package_addr<Config>(
    account: &Account<Config>,
    package_name: String
): address {
    let index: &UpgradeIndex = account.borrow_managed_data(UpgradeIndexKey(), version::current());
    *index.packages_info.get(&package_name)
}

/// Returns the package name for a given package address.
#[allow(unused_assignment)] // false positive
public fun get_package_name<Config>(
    account: &Account<Config>,
    package_addr: address
): String {
    let index: &UpgradeIndex = account.borrow_managed_data(UpgradeIndexKey(), version::current());
    let (mut i, mut package_name) = (0, b"".to_string());
    loop {
        let (name, addr) = index.packages_info.get_entry_by_idx(i);
        package_name = *name;
        if (addr == package_addr) break package_name;
        
        i = i + 1;
        if (i == index.packages_info.length()) abort EPackageDoesntExist;
    };
    
    package_name
} 

// Intent functions

/// Creates a new UpgradeAction and adds it to an intent.
public fun new_upgrade<Outcome, IW: drop>(
    intent: &mut Intent<Outcome>,
    name: String,
    digest: vector<u8>, 
    intent_witness: IW,
) {
    intent.add_action(UpgradeAction { name, digest }, intent_witness);
}    

/// Processes an UpgradeAction and returns a UpgradeTicket.
public fun do_upgrade<Config, Outcome: store, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    clock: &Clock,
    version_witness: VersionWitness,
    intent_witness: IW,
): UpgradeTicket {
    executable.intent().assert_is_account(account.addr());

    let action: &UpgradeAction = executable.next_action(intent_witness);
    assert!(
        clock.timestamp_ms() >= executable.intent().creation_time() + get_time_delay(account, action.name), 
        EUpgradeTooEarly
    );

    let cap: &mut UpgradeCap = account.borrow_managed_asset_mut(UpgradeCapKey(action.name), version_witness);
    let policy = cap.policy();

    cap.authorize_upgrade(policy, action.digest) // return ticket
}    

/// Deletes an UpgradeAction from an expired intent.
public fun delete_upgrade(expired: &mut Expired) {
    let UpgradeAction { .. } = expired.remove_action();
}

/// Creates a new CommitAction and adds it to an intent.
public fun new_commit<Outcome, IW: drop>(
    intent: &mut Intent<Outcome>,
    name: String,
    intent_witness: IW,
) {
    intent.add_action(CommitAction { name }, intent_witness);
}    

// must be called after UpgradeAction is processed, there cannot be any other action processed before
/// Commits an upgrade and updates the index with the new package address.
public fun do_commit<Config, Outcome: store, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    receipt: UpgradeReceipt,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    executable.intent().assert_is_account(account.addr());

    let action: &CommitAction = executable.next_action(intent_witness);

    let cap_mut: &mut UpgradeCap = account.borrow_managed_asset_mut(UpgradeCapKey(action.name), version_witness);
    cap_mut.commit_upgrade(receipt);
    let new_package_addr = cap_mut.package().to_address();

    // update the index with the new package address
    let index_mut: &mut UpgradeIndex = account.borrow_managed_data_mut(UpgradeIndexKey(), version_witness);
    *index_mut.packages_info.get_mut(&action.name) = new_package_addr;
}

public fun delete_commit(expired: &mut Expired) {
    let CommitAction { .. } = expired.remove_action();
}

/// Creates a new RestrictAction and adds it to an intent.
public fun new_restrict<Outcome, IW: drop>(
    intent: &mut Intent<Outcome>,
    name: String,
    policy: u8, 
    intent_witness: IW,
) {
    intent.add_action(RestrictAction { name, policy }, intent_witness);
}    

/// Processes a RestrictAction and updates the UpgradeCap policy.
public fun do_restrict<Config, Outcome: store, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    executable.intent().assert_is_account(account.addr());
    
    let action: &RestrictAction = executable.next_action(intent_witness);

    if (action.policy == package::additive_policy()) {
        let cap_mut: &mut UpgradeCap = account.borrow_managed_asset_mut(UpgradeCapKey(action.name), version_witness);
        cap_mut.only_additive_upgrades();
    } else if (action.policy == package::dep_only_policy()) {
        let cap_mut: &mut UpgradeCap = account.borrow_managed_asset_mut(UpgradeCapKey(action.name), version_witness);
        cap_mut.only_dep_upgrades();
    } else {
        let cap: UpgradeCap = account.remove_managed_asset(UpgradeCapKey(action.name), version_witness);
        package::make_immutable(cap);
    };
}

/// Deletes a RestrictAction from an expired intent.
public fun delete_restrict(expired: &mut Expired) {
    let RestrictAction { .. } = expired.remove_action();
}

// === Package Funtions ===

/// Borrows the UpgradeCap for a given package address.
public(package) fun borrow_cap<Config>(
    account: &Account<Config>, 
    package_addr: address
): &UpgradeCap {
    let name = get_package_name(account, package_addr);
    account.borrow_managed_asset(UpgradeCapKey(name), version::current())
}