/// This module shows how to create a custom intent from pre-existing actions.
/// Upgrade and Restrict are part of the account_actions package.
/// Here we use them to compose a new intent.
/// 
/// This intent represents a "one last upgrade".
/// An enforceable promise from the team to the users making the package immutable after some final adjustments.

module account_examples::upgrade_and_restrict;

use std::string::String;
use sui::{
    package::{UpgradeTicket, UpgradeReceipt},
    clock::Clock,
};
use account_protocol::{
    executable::Executable,
    account::{Account, Auth},
    intents::{Params},
    intent_interface,
};
use account_actions::package_upgrade;
use account_examples::version;

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Structs ===

/// Intent witness
public struct FinalUpgradeIntent() has copy, drop;


// === Public Functions ===

/// step 1: propose an Upgrade by passing the digest of the package build
public fun request_final_upgrade<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    package_name: String,
    digest: vector<u8>,
    _clock: &Clock,
    ctx: &mut TxContext
) {
    account.verify(auth);

    account.build_intent!(
        params,
        outcome, 
        "",
        version::current(),
        FinalUpgradeIntent(),
        ctx,
        |intent, iw| {
            // first we would like to upgrade
            package_upgrade::new_upgrade(intent, package_name, digest, iw);
            // then we would like to make the package immutable (destroy the upgrade cap)
            package_upgrade::new_restrict(intent, package_name, 255, iw);
        },
    );
}

/// step 2: multiple members have to approve the intent (account_multisig::multisig::approve_intent)
/// step 3: execute the intent and return the Executable (account_multisig::multisig::execute_intent)

/// step 4: destroy Upgrade and return the UpgradeTicket for upgrading
public fun execute_upgrade<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    clock: &Clock,
): UpgradeTicket {
    account.process_intent!(
        executable, 
        version::current(), 
        FinalUpgradeIntent(), 
        |executable, iw| package_upgrade::do_upgrade(executable, account, clock, version::current(), iw),
    )
} 

/// Need to consume the ticket to upgrade the package before completing the intent.

/// step 5: consume the receipt to commit the upgrade
public fun complete_upgrade<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    receipt: UpgradeReceipt,
) {
    account.process_intent!(
        executable,
        version::current(),
        FinalUpgradeIntent(),
        |executable, iw| package_upgrade::do_commit(executable, account, receipt, version::current(), iw)
    );
}

/// step 6: restrict the upgrade policy (destroy the upgrade cap)
public fun execute_restrict<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
) {
    account.process_intent!(
        executable,
        version::current(),
        FinalUpgradeIntent(),
        |executable, iw| package_upgrade::do_restrict(executable, account, version::current(), iw)
    );
}

/// step 7: destroy the executable with account_protocol::account::confirm_execution

/// step 8: destroy the intent to get the Expired hot potato as there is no execution left
/// and delete the actions from Expired in their own module 
