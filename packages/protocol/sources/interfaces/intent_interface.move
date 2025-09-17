/// [Intent Interface] - Functions to create intents and add actions to them.
///
/// 1. Build an intent by stacking actions into it.
/// 2. Process an intent by executing the actions sequentially.

module account_protocol::intent_interface;

// === Imports ===

use std::string::String;
use account_protocol::{
    account::{Self, Account},
    intents::{Intent, Params},
    version_witness::VersionWitness,
    executable::Executable,
};

// === Public functions ===

/// Example implementation:
/// 
/// ```move
/// 
/// public fun request_intent_name<Config, Outcome: store>(
///     auth: Auth,
///     account: &mut Account<Config>, 
///     params: Params,
///     outcome: Outcome,
///     action1: Action1,
///     action2: Action2,
///     ctx: &mut TxContext
/// ) {
///     account.verify(auth);
///     params.assert_single_execution(); // if not a recurring intent
/// 
///     account.build_intent!(
///         params,
///         outcome, 
///         b"".to_string(),
///         version::current(),
///         IntentWitness(),   
///         ctx,
///         |intent, iw| {
///             intent.add_action(action1, iw);
///             intent.add_action(action2, iw);
///         }
///     );
/// }
/// 
/// ```

/// Creates an intent with actions and adds it to the account.
public macro fun build_intent<$Config, $Outcome, $IW: drop>(
    $account: &mut Account<$Config>,
    $params: Params,
    $outcome: $Outcome,
    $managed_name: String,
    $version_witness: VersionWitness,
    $intent_witness: $IW,
    $ctx: &mut TxContext,
    $new_actions: |&mut Intent<$Outcome>, $IW|,
) {
    let mut intent = account::create_intent(
        $account,
        $params,
        $outcome,
        $managed_name,
        $version_witness, 
        $intent_witness,
        $ctx 
    );

    $new_actions(&mut intent, $intent_witness);

    account::insert_intent($account, intent, $version_witness, $intent_witness);
}

/// Example implementation:
/// 
/// ```move
/// 
/// public fun execute_intent_name<Config, Outcome: store>(
///     executable: &mut Executable<Outcome>,
///     account: &mut Account<Config>,  
/// ) {
///     account.process_intent!(
///         executable, 
///         version::current(),   
///         ConfigDepsIntent(), 
///         |executable, iw| {
///             do_action(executable, iw, <ADDITIONAL_ARG>)
///             do_other_action(executable, iw)
///         }
///     ); 
/// } 
/// 
/// ```

/// Executes the actions from the executable intent.
public macro fun process_intent<$Config, $Outcome: store, $IW: drop>(
    $account: &Account<$Config>, 
    $executable: &mut Executable<$Outcome>,
    $version_witness: VersionWitness,
    $intent_witness: $IW,
    $do_actions: |&mut Executable<$Outcome>, $IW| -> _
): _ {
    let account = $account;
    let executable = $executable;
    // let version_witness = $version_witness;
    // let intent_witness = $intent_witness;
    // ensures the package address is a dependency for this account
    account.deps().check($version_witness);
    // ensures the right account is passed
    executable.intent().assert_is_account(account.addr());
    // ensures the intent is created by the same package that creates the action
    executable.intent().assert_is_witness($intent_witness);

    $do_actions(executable, $intent_witness)
}