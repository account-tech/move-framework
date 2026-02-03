/// This module allows to manage Account settings.
/// The actions are related to the modifications of all the fields of the Account (except Intents and Config).
/// All these fields are encapsulated in the `Account` struct and each managed in their own module.
/// They are only accessible mutably via package functions defined in account.move which are used here only.
/// 
/// Dependencies are all the packages and their versions that the account can call (including this one).
/// The allowed dependencies are defined in the `Extensions` struct and are maintained by account.tech team.
/// Optionally, any package can be added to the account if unverified_allowed is true.
/// 
/// Accounts can choose to use any version of any package and must explicitly migrate to the new version.
/// This is closer to a trustless model preventing anyone with the UpgradeCap from updating the dependencies maliciously.

module account_protocol::config;

// === Imports ===

use std::string::String;
use account_protocol::{
    account::{Account, Auth},
    intents::{Expired, Params},
    executable::Executable,
    deps::{Self, Dep},
    metadata,
    version,
    intent_interface,
};
use account_extensions::extensions::Extensions;

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Structs ===

/// Intent Witness
public struct ConfigDepsIntent() has drop;
/// Intent Witness
public struct ToggleUnverifiedAllowedIntent() has drop;

/// Action struct wrapping the deps account field into an action
public struct ConfigDepsAction has store {
    deps: vector<Dep>,
}
/// Action struct wrapping the unverified_allowed account field into an action
public struct ToggleUnverifiedAllowedAction has store {}

// === Public functions ===

/// Authorized addresses can edit the metadata of the account
public fun edit_metadata<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    keys: vector<String>,
    values: vector<String>,
) {
    account.verify(auth);
    *account.metadata_mut(version::current()) = metadata::from_keys_values(keys, values);
}

/// Authorized addresses can update the existing dependencies of the account to the latest versions
public fun update_extensions_to_latest<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    extensions: &Extensions,
) {
    account.verify(auth);

    let mut i = 0;
    let mut new_names = vector<String>[];
    let mut new_addrs = vector<address>[];
    let mut new_versions = vector<u64>[];

    while (i < account.deps().length()) {
        let dep = account.deps().get_by_idx(i);
        if (extensions.is_extension(dep.name(), dep.addr(), dep.version())) {
            let (addr, version) = extensions.get_latest_for_name(dep.name());
            new_names.push_back(dep.name());
            new_addrs.push_back(addr);
            new_versions.push_back(version);
        } else {
            // else cannot automatically update to latest version so add as is
            new_names.push_back(dep.name());
            new_addrs.push_back(dep.addr());
            new_versions.push_back(dep.version());
        };
        i = i + 1;
    };

    *account.deps_mut(version::current()).inner_mut() = 
        deps::new_inner(extensions, account.deps(), new_names, new_addrs, new_versions);
}

/// Creates an intent to update the dependencies of the account
public fun request_config_deps<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    extensions: &Extensions,
    names: vector<String>,
    addresses: vector<address>,
    versions: vector<u64>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    
    let deps = deps::new_inner(extensions, account.deps(), names, addresses, versions);

    account.build_intent!(
        params,
        outcome, 
        "",
        version::current(),
        ConfigDepsIntent(),   
        ctx,
        |intent, iw| intent.add_action(ConfigDepsAction { deps }, iw),
    );
}

/// Executes an intent updating the dependencies of the account
public fun execute_config_deps<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,  
) {
    account.process_intent!(
        executable, 
        version::current(),   
        ConfigDepsIntent(), 
        |executable, iw| {
            let ConfigDepsAction { deps } = executable.next_action<_, ConfigDepsAction, _>(iw);
            *account.deps_mut(version::current()).inner_mut() = *deps;
        }
    ); 
} 

/// Deletes the ConfigDepsAction from an expired intent
public fun delete_config_deps(expired: &mut Expired) {
    let ConfigDepsAction { .. } = expired.remove_action();
}

/// Creates an intent to toggle the unverified_allowed flag of the account
public fun request_toggle_unverified_allowed<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    
    account.build_intent!(
        params,
        outcome,
        "",
        version::current(),
        ToggleUnverifiedAllowedIntent(),
        ctx,
        |intent, iw| intent.add_action(ToggleUnverifiedAllowedAction {}, iw),
    );
}

/// Executes an intent toggling the unverified_allowed flag of the account
public fun execute_toggle_unverified_allowed<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>, 
) {
    account.process_intent!(
        executable, 
        version::current(),
        ToggleUnverifiedAllowedIntent(),
        |executable, iw| {
            let _action: &ToggleUnverifiedAllowedAction = executable.next_action(iw);
            account.deps_mut(version::current()).toggle_unverified_allowed()
        },
    );    
}

/// Deletes the ToggleUnverifiedAllowedAction from an expired intent
public fun delete_toggle_unverified_allowed(expired: &mut Expired) {
    let ToggleUnverifiedAllowedAction {} = expired.remove_action();
}

