#[allow(unused_use)]
module overmind::NonFungibleToken {
  use sui::event;
  use std::vector;
  use sui::sui::SUI;
  use sui::transfer;
  use sui::url::{Self, Url};
  use sui::coin::{Self, Coin};
  use sui::coin::TreasuryCap;
  use std::string::{Self, String};
  use sui::object::{Self, UID, ID};
  use sui::balance::{Self, Balance};
  use sui::tx_context::{Self, TxContext};

  #[test_only]
  use sui::test_scenario;
  #[test_only]
  use sui::test_utils::assert_eq;

  const EInsufficientPayment: u64 = 1;
  const EInsufficientBalance: u64 = 100;

  /*
      The NonFungibleToken object represents an NFT. It contains the following fields:
      - `id` - the ID of the NFT
      - `name` - the name of the NFT
      - `description` - the description of the NFT
      - `image` - the image of the NFT
  */
  struct NonFungibleToken has key, drop {
    id: UID,
    name: String,
    description: String,
    image: Url,
  }

  /*
      The MinterCap object represents the minter cap. It contains the following fields:
      - `id` - the ID of the MinterCap object
      - `sales` - the sales balance of the MinterCap object
  */
  struct MinterCap has key {
    id: UID,
    sales: Balance<SUI>,
  }

  /*
      Event emitted when an NFT is minted in mint_nft. It contains the following fields:
      - `nft_id` - the ID of the NFT
      - `recipient` - the address of the recipient
  */
  struct NonFungibleTokenMinted has copy, drop {
    nft_id: ID,
    recipient: address
  }

  /*
      Event emitted when two NFTs are combined into a new NFT. It contains the following
      fields:
      - `nft1_id` - the ID of the first NFT
      - `nft2_id` - the ID of the second NFT
      - `new_nft_id` - the ID of the new NFT
  */
  struct NonFungibleTokenCombined has copy, drop {
    nft1_id: ID,
    nft2_id: ID,
    new_nft_id: ID,
  }

  /*
      Event emitted when an NFT is deleted in burn_nft. It contains the following fields:
      - `nft_id` - the ID of the NFT
  */
  struct NonFungibleTokenDeleted has copy, drop {
    nft_id: ID,
  }

  /*
      Event emitted whenever the sales balance is withdrawn from the MinterCap object. It
      contains the following fields:
      - `amount` - the amount withdrawn
  */
  struct SalesWithdrawn has copy, drop {
    amount: u64
  }

  /*
      Initializes the minter cap object and transfers it to the deployer of the module.
      This function is called only once during the deployment of the module.
      @param ctx - the transaction context
  */
  fun init(ctx: &mut TxContext) {
    let zero_balance: Balance<SUI> = balance::zero();
    let minter_cap = MinterCap { id: object::new(ctx), sales: zero_balance };

    transfer::transfer(minter_cap, tx_context::sender(ctx));
  }

  /*
      Mints a new NFT and transfers it to the recipient. This can only be called by the owner of
      the MinterCap object. The remaining payment is returned. Abort if the payment is below the
      price of the NFT.
      @param recipient - the address of the recipient
      @param nft_name - the name of the NFT
      @param nft_description - the description of the NFT
      @param nft_image - the image of the NFT
      @param payment_coin - the coin used to pay for the NFT
      @param minter_cap - the minter cap object
      @param ctx - the transaction context
      @return the change coin
  */
  public fun mint_nft(
    recipient: address,
    nft_name: vector<u8>,
    nft_description: vector<u8>,
    nft_image: vector<u8>,
    payment_coin: &mut Coin<SUI>,
    minter_cap: &mut MinterCap,
    ctx: &mut TxContext,
    treasury_cap: &mut TreasuryCap<SUI>,
  ): Coin<SUI> {
    let payment_amount = coin::value(payment_coin);
    assert!(payment_amount >= 1, EInsufficientPayment);

    // Initialize change_coin and conditionally assign its value
    let change_coin: Coin<SUI>;
    if (payment_amount > 1) {
      let change_amount = payment_amount - 1;
      change_coin = coin::split(payment_coin, change_amount, ctx);
    } else {
      change_coin = coin::zero(ctx);
    };

    let nft = NonFungibleToken {
      id: object::new(ctx),
      name: string::utf8(nft_name),
      description: string::utf8(nft_description),
      image: url::new_unsafe_from_bytes(nft_image),
    };

    // Increase the sales balance by 1 SUI.
    let sales_increase = coin::mint(treasury_cap, 1, ctx);
    let sales_increase_balance = coin::into_balance(sales_increase);
    balance::join(&mut minter_cap.sales, sales_increase_balance);

    // Correctly transfer the NFT to the recipient
    event::emit(NonFungibleTokenMinted { nft_id: object::id(&nft), recipient: recipient });
    transfer::transfer(nft, recipient);

    change_coin  // Return the change coin
  }

  /*
      Takes two NFTs and combines them into a new NFT. The two NFTs are deleted. This can only be
      called by the owner of the NFT objects.
      @param nft1 - the first NFT object
      @param nft2 - the second NFT object
      @param new_image_url - the image of the new NFT
      @param ctx - the transaction context
      @return the new NFT object
  */
  public fun combine_nfts(
    nft1: NonFungibleToken,
    nft2: NonFungibleToken,
    new_image_url: vector<u8>,
    ctx: &mut TxContext,
  ): NonFungibleToken {
    // Extract necessary IDs for the event.
    let nft1_id = object::id(&nft1);
    let nft2_id = object::id(&nft2);

    // Create the new NFT.
    let new_nft = NonFungibleToken {
      id: object::new(ctx),
      name: string::utf8(b"Combined NFT"),
      description: string::utf8(b"This NFT is a combination of two other NFTs."),
      image: url::new_unsafe_from_bytes(new_image_url),
    };

    // Emit the event.
    event::emit(NonFungibleTokenCombined {
      nft1_id,
      nft2_id,
      new_nft_id: object::id(&new_nft),
    });

    // Delete the original NFTs using the helper function.
    delete_nft(move (nft1));
    delete_nft(move (nft2));

    new_nft
  }

  /*
      Withdraws the sales balance from the MinterCap object. This can only be called by the owner
      of the MinterCap object.
      @param minter_cap - the minter cap object
      @param ctx - the transaction context
      @return the withdrawn coin
  */
  public fun withdraw_sales(
    minter_cap: &mut MinterCap,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    // Capture the sales balance value in a variable
    let sales_balance_value = balance::value(&minter_cap.sales);

    // Ensure the balance is not zero before proceeding to withdraw
    assert!(sales_balance_value > 0, EInsufficientBalance);

    // Now, pass the captured sales balance value to the coin::take function
    let sales_coin = coin::take(&mut minter_cap.sales, sales_balance_value, ctx);

    // Emit an event indicating the sales withdrawal
    event::emit(SalesWithdrawn { amount: sales_balance_value });

    // Return the coin representing the withdrawn sales
    sales_coin
  }

  /*
      Deletes the NFT object. This can only be called by the owner of the NFT object.
      @param nft - the NFT object
  */
  public fun burn_nft(nft: NonFungibleToken) {
    // Emit the event before consuming the NFT
    event::emit(NonFungibleTokenDeleted { nft_id: object::id(&nft) });

    delete_nft(nft);
  }

  /*
      Gets the NFT's `name`
      @param nft - the NFT object
      @return the NFT's `name`
  */
  public fun name(nft: &NonFungibleToken): String {
    nft.name
  }

  /*
      Gets the NFT's `description`
      @param nft - the NFT object
      @return the NFT's `description`
  */
  public fun description(nft: &NonFungibleToken): String {
    nft.description
  }

  /*
      Gets the NFT's `image`
      @param nft - the NFT object
      @return the NFT's `image`
  */
  public fun url(nft: &NonFungibleToken): Url {
    nft.image
  }

  // Helpers
  public fun delete_nft(token: NonFungibleToken) {
    // Emit the event before consuming the NFT
    event::emit(NonFungibleTokenDeleted { nft_id: object::id(&token) });

    // Extract the necessary fields for deletion
    let nft_id = token.id;

    // Delete using the extracted ID
    sui::object::delete(nft_id);

    // Consume the token
    move (token);
  }

  // Tests
  #[test]
  fun test_init_success() {
    let module_owner = @0xa;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 0;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    {
      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);

      assert_eq(
        balance::value(&minter_cap.sales),
        0
      );

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_mint_nft_success_perfect_change() {
    let module_owner = @0xa;
    let recipient = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 0;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    let nft_name = b"test_nft_name";
    let nft_description = b"test_nft_description";
    let nft_image = b"test_nft_image";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        recipient,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, recipient);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    {
      let nft = test_scenario::take_from_sender<NonFungibleToken>(scenario);

      assert_eq(
        nft.name,
        string::utf8(nft_name)
      );
      assert_eq(
        nft.description,
        string::utf8(nft_description)
      );
      assert_eq(
        nft.image,
        url::new_unsafe_from_bytes(nft_image)
      );

      test_scenario::return_to_sender(scenario, nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_mint_nft_success_has_change() {
    let module_owner = @0xa;
    let recipient = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 0;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    let nft_name = b"test_nft_name";
    let nft_description = b"test_nft_description";
    let nft_image = b"test_nft_image";
    let payment_amount = 1000000000;
    let change = 100000000;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        recipient,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, recipient);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    {
      let nft = test_scenario::take_from_sender<NonFungibleToken>(scenario);

      assert_eq(
        nft.name,
        string::utf8(nft_name)
      );
      assert_eq(
        nft.description,
        string::utf8(nft_description)
      );
      assert_eq(
        nft.image,
        url::new_unsafe_from_bytes(nft_image)
      );

      test_scenario::return_to_sender(scenario, nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test, expected_failure(abort_code = EInsufficientPayment)]
  fun test_mint_nft_failure_insufficient_funds() {
    let module_owner = @0xa;
    let recipient = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 0;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    let nft_name = b"test_nft_name";
    let nft_description = b"test_nft_description";
    let nft_image = b"test_nft_image";
    let payment_amount = 900000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);

      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        recipient,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_combine_nfts_success_1() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 0;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    let nft1_name = b"test_nft1_name";
    let nft1_description = b"test_nft1_description";
    let nft1_image = b"test_nft1_image";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft1_name,
        nft1_description,
        nft1_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );
    let nft1_id = vector::remove(&mut test_scenario::created(&tx), 0);

    let nft2_name = b"test_nft2_name";
    let nft2_description = b"test_nft2_description";
    let nft2_image = b"test_nft2_image";
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft2_name,
        nft2_description,
        nft2_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, nft_owner);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    let nft2_id = vector::remove(&mut test_scenario::created(&tx), 0);

    let new_image = b"new_image";
    {
      let nft1 = test_scenario::take_from_address_by_id(scenario, nft_owner, nft1_id);
      let nft2 = test_scenario::take_from_address_by_id(scenario, nft_owner, nft2_id);

      let new_nft = combine_nfts(
        nft1,
        nft2,
        new_image,
        test_scenario::ctx(scenario)
      );

      transfer::transfer(new_nft, nft_owner);
    };
    let tx = test_scenario::next_tx(scenario, nft_owner);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    {
      let new_nft = test_scenario::take_from_sender<NonFungibleToken>(scenario);

      assert_eq(
        new_nft.name,
        string::utf8(b"test_nft1_name + test_nft2_name")
      );
      assert_eq(
        new_nft.description,
        string::utf8(b"Combined NFT of test_nft1_name and test_nft2_name")
      );
      assert_eq(
        new_nft.image,
        url::new_unsafe_from_bytes(new_image)
      );

      test_scenario::return_to_sender(scenario, new_nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_combine_nfts_success_2() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 0;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    let nft1_name = b"test_nft1_name_34";
    let nft1_description = b"test_nft1_description";
    let nft1_image = b"test_nft1_image";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft1_name,
        nft1_description,
        nft1_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );
    let nft1_id = vector::remove(&mut test_scenario::created(&tx), 0);

    let nft2_name = b"test_nft2_name_12";
    let nft2_description = b"test_nft2_description";
    let nft2_image = b"test_nft2_image";
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft2_name,
        nft2_description,
        nft2_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, nft_owner);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    let nft2_id = vector::remove(&mut test_scenario::created(&tx), 0);

    let new_image = b"new_image";
    {
      let nft1 = test_scenario::take_from_address_by_id(scenario, nft_owner, nft1_id);
      let nft2 = test_scenario::take_from_address_by_id(scenario, nft_owner, nft2_id);

      let new_nft = combine_nfts(
        nft1,
        nft2,
        new_image,
        test_scenario::ctx(scenario)
      );

      transfer::transfer(new_nft, nft_owner);
    };
    let tx = test_scenario::next_tx(scenario, nft_owner);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    {
      let new_nft = test_scenario::take_from_sender<NonFungibleToken>(scenario);

      assert_eq(
        new_nft.name,
        string::utf8(b"test_nft1_name_34 + test_nft2_name_12")
      );
      assert_eq(
        new_nft.description,
        string::utf8(b"Combined NFT of test_nft1_name_34 and test_nft2_name_12")
      );
      assert_eq(
        new_nft.image,
        url::new_unsafe_from_bytes(new_image)
      );

      test_scenario::return_to_sender(scenario, new_nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_burn_nft_success() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    let tx = test_scenario::next_tx(scenario, module_owner);
    let expected_events_emitted = 0;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );

    let nft_name = b"test_nft_name";
    let nft_description = b"test_nft_description";
    let nft_image = b"test_nft_image";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, nft_owner);
    let expected_events_emitted = 1;
    let expected_created_objects = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
    assert_eq(
      vector::length(&test_scenario::created(&tx)),
      expected_created_objects
    );
    let nft_id = vector::remove(&mut test_scenario::created(&tx), 0);

    {
      let nft = test_scenario::take_from_address_by_id(scenario, nft_owner, nft_id);

      burn_nft(nft);
    };
    test_scenario::end(scenario_val);
    let expected_events_emitted = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
  }

  #[test]
  fun test_name_success_1() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    test_scenario::next_tx(scenario, module_owner);

    let nft_name = b"test_nft_name";
    let nft_description = b"test_nft_description";
    let nft_image = b"test_nft_image";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);


      test_scenario::return_to_sender(scenario, minter_cap);
    };

    let tx = test_scenario::next_tx(scenario, nft_owner);
    let nft_id = vector::remove(&mut test_scenario::created(&tx), 0);

    {
      let nft = test_scenario::take_from_address_by_id(scenario, nft_owner, nft_id);

      assert_eq(
        name(&nft),
        string::utf8(nft_name)
      );

      test_scenario::return_to_sender(scenario, nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_name_success_2() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };

    test_scenario::next_tx(scenario, module_owner);

    let nft_name = b"test_nft_name_34";
    let nft_description = b"test_nft_description";
    let nft_image = b"test_nft_image";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, nft_owner);

    let nft_id = vector::remove(&mut test_scenario::created(&tx), 0);

    {
      let nft = test_scenario::take_from_address_by_id(scenario, nft_owner, nft_id);

      assert_eq(
        name(&nft),
        string::utf8(nft_name)
      );

      test_scenario::return_to_sender(scenario, nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_description_success_1() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    test_scenario::next_tx(scenario, module_owner);

    let nft_name = b"test_nft_name";
    let nft_description = b"test_nft_description";
    let nft_image = b"test_nft_image";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);


      test_scenario::return_to_sender(scenario, minter_cap);
    };

    let tx = test_scenario::next_tx(scenario, nft_owner);
    let nft_id = vector::remove(&mut test_scenario::created(&tx), 0);

    {
      let nft = test_scenario::take_from_address_by_id(scenario, nft_owner, nft_id);

      assert_eq(
        description(&nft),
        string::utf8(nft_description)
      );

      test_scenario::return_to_sender(scenario, nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_description_success_2() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };

    test_scenario::next_tx(scenario, module_owner);

    let nft_name = b"test_nft_name_34";
    let nft_description = b"test_nft_description43";
    let nft_image = b"test_nft_image2";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, nft_owner);

    let nft_id = vector::remove(&mut test_scenario::created(&tx), 0);

    {
      let nft = test_scenario::take_from_address_by_id(scenario, nft_owner, nft_id);

      assert_eq(
        description(&nft),
        string::utf8(nft_description)
      );

      test_scenario::return_to_sender(scenario, nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_url_success_1() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };
    test_scenario::next_tx(scenario, module_owner);

    let nft_name = b"test_nft_name";
    let nft_description = b"test_nft_description";
    let nft_image = b"test_nft_image";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);


      test_scenario::return_to_sender(scenario, minter_cap);
    };

    let tx = test_scenario::next_tx(scenario, nft_owner);
    let nft_id = vector::remove(&mut test_scenario::created(&tx), 0);

    {
      let nft = test_scenario::take_from_address_by_id(scenario, nft_owner, nft_id);

      assert_eq(
        url(&nft),
        url::new_unsafe_from_bytes(nft_image)
      );

      test_scenario::return_to_sender(scenario, nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_url_success_2() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };

    test_scenario::next_tx(scenario, module_owner);

    let nft_name = b"test_nft_name_34";
    let nft_description = b"test_nft_description43";
    let nft_image = b"test_nft_image2";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::next_tx(scenario, nft_owner);

    let nft_id = vector::remove(&mut test_scenario::created(&tx), 0);

    {
      let nft = test_scenario::take_from_address_by_id(scenario, nft_owner, nft_id);

      assert_eq(
        url(&nft),
        url::new_unsafe_from_bytes(nft_image)
      );

      test_scenario::return_to_sender(scenario, nft);
    };

    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_withdraw_sales_success_sale_balance_zero() {
    let module_owner = @0xa;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };

    test_scenario::next_tx(scenario, module_owner);

    let expected_sales_amount = 0;
    {
      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);

      let sales_coin = withdraw_sales(
        &mut minter_cap,
        test_scenario::ctx(scenario)
      );

      assert_eq(
        coin::value(&sales_coin),
        expected_sales_amount
      );
      coin::burn_for_testing(sales_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::end(scenario_val);
    let expected_events_emitted = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
  }

  #[test]
  fun test_withdraw_sales_success_sales_balance_non_zero() {
    let module_owner = @0xa;
    let nft_owner = @0xb;

    let scenario_val = test_scenario::begin(module_owner);
    let scenario = &mut scenario_val;

    {
      init(test_scenario::ctx(scenario));
    };

    test_scenario::next_tx(scenario, module_owner);

    let nft_name = b"test_nft_name_34";
    let nft_description = b"test_nft_description43";
    let nft_image = b"test_nft_image2";
    let payment_amount = 1000000000;
    let change = 0;
    {
      let payment_coin = sui::coin::mint_for_testing<SUI>(
        payment_amount + change,
        test_scenario::ctx(scenario)
      );

      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);
      let treasury_cap = sui::coin::create_treasury_cap_for_testing<SUI>(
        test_scenario::ctx(scenario)
      );

      mint_nft(
        nft_owner,
        nft_name,
        nft_description,
        nft_image,
        &mut payment_coin,
        &mut minter_cap,
        test_scenario::ctx(scenario),
        &mut treasury_cap
      );

      assert_eq(
        coin::value(&payment_coin),
        change
      );
      coin::burn_for_testing(payment_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };

    test_scenario::next_tx(scenario, module_owner);

    let expected_sales_amount = 1000000000;
    {
      let minter_cap = test_scenario::take_from_sender<MinterCap>(scenario);

      let sales_coin = withdraw_sales(
        &mut minter_cap,
        test_scenario::ctx(scenario)
      );

      assert_eq(
        coin::value(&sales_coin),
        expected_sales_amount
      );
      coin::burn_for_testing(sales_coin);

      test_scenario::return_to_sender(scenario, minter_cap);
    };
    let tx = test_scenario::end(scenario_val);
    let expected_events_emitted = 1;
    assert_eq(
      test_scenario::num_user_events(&tx),
      expected_events_emitted
    );
  }
}
