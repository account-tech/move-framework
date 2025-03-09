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
};
use account_actions::{
    transfer as acc_transfer,
    vesting,
    vault,
    version,
};

// === Errors ===

const EObjectsRecipientsNotSameLength: u64 = 0;

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
    outcome: Outcome,
    account: &mut Account<Config>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    coin_id: ID,
    coin_amount: u64,
    vault_name: String,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        WithdrawAndTransferToVaultIntent(),
        ctx
    );

    owned::new_withdraw(
        &mut intent, account, coin_id, version::current(), WithdrawAndTransferToVaultIntent()
    );
    vault::new_deposit<_, _, CoinType, _>(
        &mut intent, account, vault_name, coin_amount, version::current(), WithdrawAndTransferToVaultIntent()
    );

    account.add_intent(intent, version::current(), WithdrawAndTransferToVaultIntent());
}

/// Executes a WithdrawAndTransferToVaultIntent, deposits a coin owned by the account into a vault.
public fun execute_withdraw_and_transfer_to_vault<Config, Outcome: store, CoinType: drop>(
    mut executable: Executable, 
    account: &mut Account<Config>, 
    receiving: Receiving<Coin<CoinType>>,
) {
    let object = owned::do_withdraw<_, Outcome, _, _>(&mut executable, account, receiving, version::current(), WithdrawAndTransferToVaultIntent());
    vault::do_deposit<_, Outcome, _, _>(&mut executable, account, object, version::current(), WithdrawAndTransferToVaultIntent());
    
    account.confirm_execution<_, Outcome, _>(executable, version::current(), WithdrawAndTransferToVaultIntent());
}

/// Creates a WithdrawAndTransferIntent and adds it to an Account.
public fun request_withdraw_and_transfer<Config, Outcome: store>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    object_ids: vector<ID>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(recipients.length() == object_ids.length(), EObjectsRecipientsNotSameLength);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        WithdrawAndTransferIntent(),
        ctx
    );

    object_ids.zip_do!(recipients, |object_id, recipient| {
        owned::new_withdraw(&mut intent, account, object_id, version::current(), WithdrawAndTransferIntent());
        acc_transfer::new_transfer(&mut intent, account, recipient, version::current(), WithdrawAndTransferIntent());
    });

    account.add_intent(intent, version::current(), WithdrawAndTransferIntent());
}

/// Executes a WithdrawAndTransferIntent, transfers an object owned by the account. Can be looped over.
public fun execute_withdraw_and_transfer<Config, Outcome: store, T: key + store>(
    executable: &mut Executable, 
    account: &mut Account<Config>, 
    receiving: Receiving<T>,
) {
    let object = owned::do_withdraw<_, Outcome, _, _>(executable, account, receiving, version::current(), WithdrawAndTransferIntent());
    acc_transfer::do_transfer<_, Outcome, _, _>(executable, account, object, version::current(), WithdrawAndTransferIntent());
}

/// Completes a WithdrawAndTransferIntent, destroys the executable after looping over the transfers.
public fun complete_withdraw_and_transfer<Config, Outcome: store>(
    executable: Executable,
    account: &Account<Config>,
) {
    account.confirm_execution<_, Outcome, _>(executable, version::current(), WithdrawAndTransferIntent());
}

/// Creates a WithdrawAndVestIntent and adds it to an Account.
public fun request_withdraw_and_vest<Config, Outcome: store>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    coin_id: ID, // coin owned by the account, must have the total amount to be paid
    start_timestamp: u64,
    end_timestamp: u64, 
    recipient: address,
    ctx: &mut TxContext
) {
    account.verify(auth);
    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        WithdrawAndVestIntent(),
        ctx
    );
    
    owned::new_withdraw(
        &mut intent, account, coin_id, version::current(), WithdrawAndVestIntent()
    );
    vesting::new_vest(
        &mut intent, account, start_timestamp, end_timestamp, recipient, version::current(), WithdrawAndVestIntent()
    );
    account.add_intent(intent, version::current(), WithdrawAndVestIntent());
}

/// Executes a WithdrawAndVestIntent, withdraws a coin and creates a vesting.
public fun execute_withdraw_and_vest<Config, Outcome: store, C: drop>(
    mut executable: Executable, 
    account: &mut Account<Config>, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    let coin: Coin<C> = owned::do_withdraw<_, Outcome, _, _>(&mut executable, account, receiving, version::current(), WithdrawAndVestIntent());
    vesting::do_vest<_, Outcome, _, _>(&mut executable, account, coin, version::current(), WithdrawAndVestIntent(), ctx);
    account.confirm_execution<_, Outcome, _>(executable, version::current(), WithdrawAndVestIntent());
}