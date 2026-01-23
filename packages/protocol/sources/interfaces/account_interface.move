/// [Account Interface] - High level functions to create required "methods" for the account.
///
/// 1. Define a new Account type with a specific config and default dependencies.
/// 2. Define a mechanism to authenticate an address to grant permission to call certain functions.
/// 3. Define a way to modify the outcome of an intent.
/// 4. Define an `Outcome.validate()` that will be called upon intent execution.

module account_protocol::account_interface;

// === Imports ===

use std::string::String;
use sui::clock::Clock;
use account_protocol::{
    account::{Self, Account, Auth},
    version_witness::VersionWitness,
    executable::Executable,
};

// === Public functions ===

/// Example implementation:
/// 
/// ```move
/// 
/// public fun authenticate(
///     account: &Account<Multisig, Approvals>,
///     ctx: &TxContext
/// ): Auth {
///     authenticate!(
///        account, 
///        version::current(), 
///        Witness(), 
///        || account.config().assert_is_member(ctx)
///     )
/// }
/// 
/// ```

/// Returns an Auth if the conditions passed are met (used to create intents and more).
public macro fun create_auth<$Config, $CW: drop>(
    $account: &Account<$Config>,
    $version_witness: VersionWitness,
    $config_witness: $CW,
    $grant_permission: ||, // condition to grant permission, must throw if not met
): Auth {
    let account = $account;

    $grant_permission();
    
    account.new_auth($version_witness, $config_witness)
}

/// Example implementation:
/// 
/// ```move
/// 
/// public fun approve_intent<Config>(
///     account: &mut Account<Config>, 
///     key: String,
///     ctx: &TxContext
/// ) {
///     <PREPARE_DATA>
///     
///     resolve_intent!(
///         account, 
///         key, 
///         version::current(), 
///         Witness(), 
///         |outcome_mut| {
///             <DO_SOMETHING>
///         }
///     );
/// }
/// 
/// ```

/// Modifies the outcome of an intent.
public macro fun resolve_intent<$Config, $Outcome, $CW: drop>(
    $account: &mut Account<$Config>,
    $key: String,
    $version_witness: VersionWitness,
    $config_witness: $CW,
    $modify_outcome: |&mut $Outcome|,
) {
    let account = $account;

    let outcome_mut = account
        .intents_mut($version_witness, $config_witness)
        .get_mut($key)
        .outcome_mut<$Outcome>();

    $modify_outcome(outcome_mut);
}

/// Example implementation:
/// 
/// IMPORTANT: You must provide an Outcome.validate() function that will be called automatically.
/// It must take the outcome by value, a reference to the Config and the role of the intent even if not used.
/// 
/// ```move
/// 
/// public fun execute_intent(
///     account: &mut Account<Config>, 
///     key: String, 
///     clock: &Clock,
/// ): Executable<Outcome> {
///     execute_intent!<_, Outcome, _>(account, key, clock, version::current(), Witness())
/// }
/// 
/// fun validate_outcome(
///     outcome: Outcome, 
///     config: &Config,
///     role: String,
/// ) {
///     let Outcome { fields, .. } = outcome;
/// 
///     assert!(<CHECK_CONDITIONS>);
/// }
/// 
/// ``` 

/// Validates the outcome of an intent and returns an executable.
public macro fun execute_intent<$Config, $Outcome, $CW: drop>(
    $account: &mut Account<$Config>,
    $key: String,
    $clock: &Clock,
    $version_witness: VersionWitness,
    $config_witness: $CW,
    $validate_outcome: |$Outcome|,
): Executable<$Outcome> {
    let (outcome, executable) = account::create_executable<_, $Outcome, _>(
        $account, $key, $clock, $version_witness, $config_witness
    );

    $validate_outcome(outcome);

    executable
}