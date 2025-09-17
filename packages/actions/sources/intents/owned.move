module account_actions::owned_intents;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    coin::Coin,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    owned,
    intents::Params,
    intent_interface,
};
use account_actions::{
    transfer as acc_transfer,
    vesting,
    vault,
    version,
};

// === Aliases ===

use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const EObjectsRecipientsNotSameLength: u64 = 0;
const ENoVault: u64 = 1;

// === Structs ===

/// Intent Witness defining the intent to withdraw a coin and deposit it into a vault.
public struct WithdrawAndTransferToVaultIntent() has copy, drop;
/// Intent Witness defining the intent to withdraw and transfer multiple objects.
public struct WithdrawAndTransferIntent() has copy, drop;
/// Intent Witness defining the intent to withdraw a coin and create a vesting.
public struct WithdrawAndVestIntent() has copy, drop;

// === Public functions ===

/// Creates a WithdrawAndTransferToVaultIntent and adds it to an Account.
public fun request_withdraw_and_transfer_to_vault<Config, Outcome: store, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    coin_id: ID,
    coin_amount: u64,
    vault_name: String,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(vault::has_vault(account, vault_name), ENoVault);

    intent_interface::build_intent!(
        account,
        params,
        outcome,
        b"".to_string(),
        version::current(),
        WithdrawAndTransferToVaultIntent(),
        ctx,
        |intent, iw| {
            owned::new_withdraw(intent, account, coin_id, iw);
            vault::new_deposit<_, CoinType, _>(intent, vault_name, coin_amount, iw);
        }
    );
}

/// Executes a WithdrawAndTransferToVaultIntent, deposits a coin owned by the account into a vault.
public fun execute_withdraw_and_transfer_to_vault<Config, Outcome: store, CoinType: drop>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    receiving: Receiving<Coin<CoinType>>,
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndTransferToVaultIntent(),
        |executable, iw| {
            let object = owned::do_withdraw(executable, account, receiving, iw);
            vault::do_deposit<_, _, CoinType, _>(executable, account, object, version::current(), iw);
        }
    );
}

/// Creates a WithdrawAndTransferIntent and adds it to an Account.
public fun request_withdraw_and_transfer<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    object_ids: vector<ID>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(object_ids.length() == recipients.length(), EObjectsRecipientsNotSameLength);

    intent_interface::build_intent!(
        account,
        params,
        outcome,
        b"".to_string(),
        version::current(),
        WithdrawAndTransferIntent(),
        ctx,
        |intent, iw| object_ids.zip_do!(recipients, |object_id, recipient| {
            owned::new_withdraw(intent, account, object_id, iw);
            acc_transfer::new_transfer(intent, recipient, iw);
        })
    );
}

/// Executes a WithdrawAndTransferIntent, transfers an object owned by the account. Can be looped over.
public fun execute_withdraw_and_transfer<Config, Outcome: store, T: key + store>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    receiving: Receiving<T>,
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndTransferIntent(),
        |executable, iw| {
            let object = owned::do_withdraw(executable, account, receiving, iw);
            acc_transfer::do_transfer(executable, object, iw);
        }
    );
}

/// Creates a WithdrawAndVestIntent and adds it to an Account.
public fun request_withdraw_and_vest<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    coin_id: ID, // coin owned by the account, must have the total amount to be paid
    start_timestamp: u64,
    end_timestamp: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    intent_interface::build_intent!(
        account,
        params,
        outcome,
        b"".to_string(),
        version::current(),
        WithdrawAndVestIntent(),
        ctx,
        |intent, iw| {
            owned::new_withdraw(intent, account, coin_id, iw);
            vesting::new_vest(intent, start_timestamp, end_timestamp, recipient, iw);
        }
    );
}

/// Executes a WithdrawAndVestIntent, withdraws a coin and creates a vesting.
public fun execute_withdraw_and_vest<Config, Outcome: store, C: drop>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndVestIntent(),
        |executable, iw| {
            let coin = owned::do_withdraw(executable, account, receiving, iw);
            vesting::do_vest(executable, coin, iw, ctx);
        }
    );
}