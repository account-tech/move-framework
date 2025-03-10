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
    intents::{Intent, Expired},
    executable::Executable,
    deps::{Self, Deps},
    metadata,
    version,
    intent_interface,
    action_interface,
};
use account_extensions::extensions::Extensions;

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;
use fun action_interface::init_action as Intent.init_action;
use fun action_interface::do_action as Executable.do_action;

// === Structs ===

/// Intent Witness
public struct ConfigDepsIntent() has drop;
/// Intent Witness
public struct ToggleUnverifiedAllowedIntent() has drop;

/// Action struct wrapping the deps account field into an action
public struct ConfigDepsAction has store {
    deps: Deps,
}
/// Action struct wrapping the unverified_allowed account field into an action
public struct ToggleUnverifiedAllowedAction has store {
    new_value: bool,
}

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
        };
        // else cannot automatically update to latest version
        i = i + 1;
    };

    *account.deps_mut(version::current()) = 
        deps::new(extensions, account.deps().unverified_allowed(), new_names, new_addrs, new_versions);
}

// TODO: gather all common args in one Struct

/// Creates an intent to update the dependencies of the account
public fun request_config_deps<Config, Outcome: store>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    extensions: &Extensions,
    names: vector<String>,
    addresses: vector<address>,
    versions: vector<u64>,
    ctx: &mut TxContext
) {
    account.verify(auth);

    account.build_intent!(
        key, 
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome, 
        version::current(),
        ConfigDepsIntent(),   
        ctx,
        |intent| new_config_deps_action(intent, extensions, names, addresses, versions, ConfigDepsIntent()),
    );

    // let deps = deps::new(extensions, account.deps().unverified_allowed(), names, addresses, versions);

    // account.add_action(&mut intent, ConfigDepsAction { deps }, version::current(), ConfigDepsIntent());
    // account.add_intent(intent, version::current(), ConfigDepsIntent());
}

public fun new_config_deps_action<Config>(
    intent: &mut account_protocol::intents::Intent<Config>,
    extensions: &Extensions,
    names: vector<String>,
    addresses: vector<address>,
    versions: vector<u64>,
    intent_witness: ConfigDepsIntent,
) {
    intent.init_action!(
        intent_witness,
        || ConfigDepsAction { deps: deps::new(extensions, false, names, addresses, versions) },
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
        |executable| do_config_deps(executable, account),
    ); 
} 

public fun do_config_deps<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>, 
) { 
    executable.do_action!( 
        account,
        |action: &ConfigDepsAction| *account.deps_mut(version::current()) = action.deps,
    );
}

/// Deletes the ConfigDepsAction from an expired intent
public fun delete_config_deps(expired: &mut Expired) {
    let ConfigDepsAction { .. } = expired.remove_action();
}

// /// Creates an intent to toggle the unverified_allowed flag of the account
// public fun request_toggle_unverified_allowed<Config, Outcome: store>(
//     auth: Auth,
//     outcome: Outcome,
//     account: &mut Account<Config>, 
//     key: String,
//     description: String,
//     execution_time: u64,
//     expiration_time: u64,
//     ctx: &mut TxContext
// ) {
//     account.verify(auth);

//     let mut intent = account.create_intent!(
//         key,
//         description,
//         vector[execution_time],
//         expiration_time,
//         b"".to_string(),
//         outcome,
//         version::current(),
//         ToggleUnverifiedAllowedIntent(),
//         ctx
//     );

//     let new_value = !account.deps().unverified_allowed();

//     account.add_action(&mut intent, ToggleUnverifiedAllowedAction { new_value }, version::current(), ToggleUnverifiedAllowedIntent());
//     account.add_intent(intent, version::current(), ToggleUnverifiedAllowedIntent());
// }

// /// Executes an intent toggling the unverified_allowed flag of the account
// public fun execute_toggle_unverified_allowed<Config, Outcome: store>(
//     mut executable: Executable,
//     account: &mut Account<Config>, 
// ) {
//     account.process_action!<_, Outcome, ToggleUnverifiedAllowedAction, _>(
//         &mut executable, 
//         |_action| account.deps_mut(version::current()).toggle_unverified_allowed(),
//         version::current(), 
//         ToggleUnverifiedAllowedIntent(),
//     );    
//     account.confirm_execution<_, Outcome, _>(executable, version::current(), ToggleUnverifiedAllowedIntent());
// }

// /// Deletes the ToggleUnverifiedAllowedAction from an expired intent
// public fun delete_toggle_unverified_allowed(expired: &mut Expired) {
//     let ToggleUnverifiedAllowedAction { .. } = expired.remove_action();
// }

