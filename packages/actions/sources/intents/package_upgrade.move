module account_actions::package_upgrade_intents;

// === Imports ===

use std::string::String;
use sui::{
    package::{Self, UpgradeTicket, UpgradeReceipt},
    clock::Clock,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    intents::Params,
    intent_interface,
};
use account_actions::{
    package_upgrade,
    version,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const EInvalidPolicy: u64 = 1;
const EPolicyShouldRestrict: u64 = 2;
const ENoLock: u64 = 3;
const ETimeDelay: u64 = 4;

// === Structs ===

/// Intent Witness defining the intent to upgrade a package.
public struct UpgradePackageIntent() has copy, drop;
/// Intent Witness defining the intent to restrict an UpgradeCap.
public struct RestrictPolicyIntent() has copy, drop;

// === Public Functions ===

/// Creates an UpgradePackageIntent and adds it to an Account.
public fun request_upgrade_package<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    package_name: String,
    digest: vector<u8>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    assert!(package_upgrade::has_cap(account, package_name), ENoLock);
    assert!(
        params.execution_times()[0] >= params.creation_time() + package_upgrade::get_time_delay(account, package_name), 
        ETimeDelay
    );

    account.build_intent!(
        params,
        outcome,
        package_name,
        version::current(),
        UpgradePackageIntent(),
        ctx,
        |intent, iw| {
            package_upgrade::new_upgrade(intent, package_name, digest, iw);
            package_upgrade::new_commit(intent, package_name, iw);
        },
    );
}

/// Executes an UpgradePackageIntent, returns the UpgradeTicket for upgrading.
public fun execute_upgrade_package<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    clock: &Clock,
): UpgradeTicket {
    account.process_intent!(
        executable,
        version::current(),
        UpgradePackageIntent(),
        |executable, iw| package_upgrade::do_upgrade(executable, account, clock, version::current(), iw)
    )
}    

/// Need to consume the ticket to upgrade the package before completing the intent.

public fun execute_commit_upgrade<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    receipt: UpgradeReceipt,
) {
    account.process_intent!(
        executable,
        version::current(),
        UpgradePackageIntent(),
        |executable, iw| package_upgrade::do_commit(executable, account, receipt, version::current(), iw)
    )
}

/// Creates a RestrictPolicyIntent and adds it to an Account.
public fun request_restrict_policy<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    package_name: String,
    policy: u8,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    let current_policy = package_upgrade::get_cap_policy(account, package_name);
    assert!(policy > current_policy, EPolicyShouldRestrict);
    assert!(
        policy == package::additive_policy() ||
        policy == package::dep_only_policy() ||
        policy == 255, // make immutable
        EInvalidPolicy
    );

    account.build_intent!(
        params,
        outcome,
        package_name,
        version::current(),
        RestrictPolicyIntent(),
        ctx,
        |intent, iw| package_upgrade::new_restrict(intent, package_name, policy, iw),
    );
}

/// Restricts the upgrade policy.
public fun execute_restrict_policy<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
) {
    account.process_intent!(
        executable,
        version::current(),
        RestrictPolicyIntent(),
        |executable, iw| package_upgrade::do_restrict(executable, account, version::current(), iw)
    );
}