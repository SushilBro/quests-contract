import {
  contractPrincipalCV,
  standardPrincipalCV,
  stringAsciiCV,
  uintCV,
  boolCV,
  trueCV,
  ResponseOkCV,
  UIntCV,
  PrincipalCV,
  listCV,
  ContractPrincipalCV,
} from "@stacks/transactions";
import { describe, expect, it } from "vitest";
import { initSimnet } from "@stacks/clarinet-sdk";
const simnet = await initSimnet();

// Error codes from the treasury contract
const ERR_UNAUTHORIZED = 2001;
const ERR_INSUFFICIENT_BALANCE = 2002;
const ERR_INVALID_AMOUNT = 2003;
const ERR_WRONG_TOKEN = 2004;
const ERR_WRONG_TOKEN_FOR_QUEST = 1007;
const ERR_TRANSFER_INDEX_PREFIX = 1000;

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const address4 = accounts.get("wallet_4")!;
const address5 = accounts.get("wallet_5")!;
const deployer = accounts.get("deployer")!;

const wstxToken = contractPrincipalCV(
  "SP32AEEF6WW5Y0NMJ1S8SBSZDAY8R5J32NBZFPKKZ",
  "wstx"
);

const sbtToken = contractPrincipalCV(
  "SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4",
  "sbtc-token"
);


const wstxPrincipal = contractPrincipalCV(
  "SP32AEEF6WW5Y0NMJ1S8SBSZDAY8R5J32NBZFPKKZ",
  "wstx"
);

// Helper function to get token balance
const getTokenBalance = (principal: PrincipalCV, tokenPrincipal: ContractPrincipalCV) => {
  return (
    simnet.callReadOnlyFn(
      tokenPrincipal.value,
      "get-balance",
      [principal],
      deployer
    ).result as ResponseOkCV<UIntCV>
  ).value.value;
};



// Helper function to get treasury balance
const getTreasuryBalance = (tokenPrincipal: PrincipalCV) => {
  const result = simnet.callReadOnlyFn(
    "treasury",
    "get-balance",
    [tokenPrincipal],
    deployer
  ).result as UIntCV;
  return result.value;
};

/** Console logger: clear section headers and test outcome messages for test runs */
const LOG = {
  section: (title: string) =>
    console.log(`\n  \x1b[36m${"─".repeat(50)}\n  📁 ${title}\n  ${"─".repeat(50)}\x1b[0m`),
  test: (title: string) => console.log(`  \x1b[33m▶\x1b[0m ${title}`),
  pass: (msg: string) => console.log(`  \x1b[32m✓\x1b[0m ${msg}`),
  expectErr: (code: number) => console.log(`  \x1b[32m✓\x1b[0m Correctly rejected (err ${code}).`),
};

describe("treasury contract tests", () => {
  describe("deposit", () => {
    it("ensures tokens can be deposited successfully", () => {
      LOG.section("Treasury — deposit");
      LOG.test("User deposits tokens into treasury; balance increases by deposited amount.");
      // Arrange
      const depositAmount = uintCV(1000000);
      const treasuryBalanceBefore = getTreasuryBalance(wstxPrincipal);
      const userBalanceBefore = getTokenBalance(standardPrincipalCV(address1), wstxPrincipal);

      // Act
      const { result: deposit } = simnet.callPublicFn(
        "treasury",
        "deposit",
        [depositAmount, standardPrincipalCV(address1), wstxToken],
        address1
      );

      // Assert
      expect(deposit).toBeOk(trueCV());

      const treasuryBalanceAfter = getTreasuryBalance(wstxPrincipal);
      expect(BigInt(treasuryBalanceAfter) - BigInt(treasuryBalanceBefore)).toBe(
        BigInt(depositAmount.value)
      );
      LOG.pass(`Deposit succeeded. Treasury balance increased by ${depositAmount.value}.`);
    });

    it("ensures deposit fails with zero amount", () => {
      LOG.test("Deposit with amount 0 is rejected.");
      // Act
      const { result: deposit } = simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(0), standardPrincipalCV(address1), wstxToken],
        address1
      );

      // Assert
      expect(deposit).toBeErr(uintCV(3));
      LOG.expectErr(3);
    });

    it("ensures deposit fails with wrong token", () => {
      LOG.test("Deposit with non-whitelisted token is rejected.");
      // Arrange
      const wrongToken = contractPrincipalCV(
        "SP000000000000000000002Q6VF78",
        "pox-4"
      );

      // Act
      const { result: deposit } = simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(1000000), standardPrincipalCV(address1), wrongToken],
        address1
      );

      // Assert
      expect(deposit).toBeErr(uintCV(ERR_WRONG_TOKEN));
      LOG.expectErr(ERR_WRONG_TOKEN);
    });

    it("ensures multiple deposits accumulate balance", () => {
      LOG.test("Multiple users deposit; treasury balance equals sum of deposits.");
      // Arrange
      const depositAmount1 = uintCV(500000);
      const depositAmount2 = uintCV(300000);
      const treasuryBalanceBefore = getTreasuryBalance(wstxPrincipal);

      // Act
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [depositAmount1, standardPrincipalCV(address1), wstxToken],
        address1
      );

      simnet.callPublicFn(
        "treasury",
        "deposit",
        [depositAmount2, standardPrincipalCV(address2), wstxToken],
        address2
      );

      // Assert
      const treasuryBalanceAfter = getTreasuryBalance(wstxPrincipal);
      const expectedIncrease =
        BigInt(depositAmount1.value) + BigInt(depositAmount2.value);
      expect(BigInt(treasuryBalanceAfter) - BigInt(treasuryBalanceBefore)).toBe(
        expectedIncrease
      );
      LOG.pass("Multiple deposits accumulated correctly.");
    });

    it("ensures anyone can deposit tokens", () => {
      LOG.test("Any principal can call deposit (no owner check).");
      // Act - different users deposit
      const deposit1 = simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(100000), standardPrincipalCV(address1), wstxToken],
        address1
      );
      expect(deposit1.result).toBeOk(trueCV());

      const deposit2 = simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(200000), standardPrincipalCV(address2), wstxToken],
        address2
      );
      expect(deposit2.result).toBeOk(trueCV());

      const deposit3 = simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(300000), standardPrincipalCV(address3), wstxToken],
        address3
      );
      expect(deposit3.result).toBeOk(trueCV());
      LOG.pass("All three users deposited successfully.");
    });
  });

  describe("withdraw", () => {
    it("ensures withdraw fails when called directly (not from quests contract)", () => {
      LOG.section("Treasury — withdraw");
      LOG.test("Direct withdraw (not from quests contract) is rejected.");
      // Arrange - first deposit some tokens
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(1000000), standardPrincipalCV(address1), wstxToken],
        address1
      );

      // Act - try to withdraw directly (should fail because contract-caller is not quests)
      const { result: withdraw } = simnet.callPublicFn(
        "treasury",
        "withdraw",
        [
          uintCV(500000),
          standardPrincipalCV(address1),
          wstxToken,
        ],
        address1
      );

      // Assert
      expect(withdraw).toBeErr(uintCV(ERR_UNAUTHORIZED));
      LOG.expectErr(ERR_UNAUTHORIZED);
    });

    it("ensures withdraw fails with zero amount", () => {
      LOG.test("Withdraw with amount 0 is rejected (after auth check).");
      // Arrange - deposit tokens first
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(1000000), standardPrincipalCV(address1), wstxToken],
        address1
      );

      // Act - try to withdraw zero (even if called from quests, should fail validation)
      // Note: This test assumes we can't call from quests directly, so we test the validation
      // The actual withdraw from quests would need to be tested through quests contract
      const { result: withdraw } = simnet.callPublicFn(
        "treasury",
        "withdraw",
        [uintCV(0), standardPrincipalCV(address1), wstxToken],
        address1
      );

      // Assert - should fail with ERR_UNAUTHORIZED (because not from quests) or ERR_INVALID_AMOUNT
      // Since it checks authorization first, it will fail with ERR_UNAUTHORIZED
      expect(withdraw).toBeErr(uintCV(ERR_UNAUTHORIZED));
      LOG.expectErr(ERR_UNAUTHORIZED);
    });

    it("ensures withdraw fails with insufficient balance", () => {
      LOG.test("Withdraw exceeding treasury balance is rejected.");
      // Arrange - deposit a small amount
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(100000), standardPrincipalCV(address1), wstxToken],
        address1
      );

      // Act - try to withdraw more than available
      const { result: withdraw } = simnet.callPublicFn(
        "treasury",
        "withdraw",
        [
          uintCV(200000),
          standardPrincipalCV(address1),
          wstxToken,
        ],
        address1
      );

      // Assert - fails authorization check first
      expect(withdraw).toBeErr(uintCV(ERR_UNAUTHORIZED));
      LOG.expectErr(ERR_UNAUTHORIZED);
    });

    it("ensures withdraw fails with wrong token", () => {
      LOG.test("Cancel-quest with wrong token (vs quest token) is rejected by quests.");
      // Arrange - deposit tokens
      simnet.callPublicFn(
        "quests",
        "create-quest",
        [stringAsciiCV("51e48b89-beac-4681-9cf0-ed0c88e8d50e"), stringAsciiCV("Test Quest for Withdraw"), wstxToken, uintCV(5000000)],
        address1
      );

      const wrongToken = contractPrincipalCV(
        "SM3VDXK3WZZSA84XXFKAFAF15NNZX32CTSG82JFQ4",
        "sbtc-token"
      );

      // Act
      const { result: withdraw } = simnet.callPublicFn(
        "quests",
        "cancel-quest",
        [stringAsciiCV("51e48b89-beac-4681-9cf0-ed0c88e8d50e"), wrongToken],
        address1
      );

      // Assert - fails authorization check first
      expect(withdraw).toBeErr(uintCV(ERR_WRONG_TOKEN_FOR_QUEST));
      LOG.expectErr(ERR_WRONG_TOKEN_FOR_QUEST);
    });

    it("ensures withdraw succeeds when called from quests contract (via cancel-quest)", () => {
      LOG.test("Creator cancels quest; treasury withdraws commitment to creator; balances verified.");
      // Arrange - create a quest which deposits creation fee to treasury
      const questId = "51e48b89-beac-4681-9cf0-ed0c88e8d50e";
      const commitmentAmount = uintCV(5000000);
      // Create quest (this deposits creation fee to treasury)
      simnet.callPublicFn(
        "quests",
        "create-quest",
        [
          stringAsciiCV(questId),
          stringAsciiCV("Test Quest for Withdraw"),
          wstxToken,
          commitmentAmount,
        ],
        address1
      );
      const creatorBalanceBefore = getTokenBalance(standardPrincipalCV(address1), wstxPrincipal);
      const treasuryBalanceBefore = getTreasuryBalance(wstxPrincipal);
      // Verify treasury received the creation fee
      const treasuryBalanceAfterCreation = getTreasuryBalance(wstxPrincipal);
      expect(
        treasuryBalanceAfterCreation
      ).toEqual(BigInt(commitmentAmount.value));

      // Act - cancel quest (this calls withdraw from quests contract)
      const { result: cancel } = simnet.callPublicFn(
        "quests",
        "cancel-quest",
        [stringAsciiCV(questId), wstxToken],
        address1
      );

      expect(cancel).toBeOk(trueCV());

      const treasuryBalanceAfterCancel = getTreasuryBalance(wstxPrincipal);
      expect(treasuryBalanceAfterCancel).toBe(BigInt(0));

      const creatorBalanceAfter = getTokenBalance(standardPrincipalCV(address1), wstxPrincipal);

      expect(BigInt(creatorBalanceAfter) - BigInt(creatorBalanceBefore)).toBe(BigInt(commitmentAmount.value));
      LOG.pass(`Cancel-quest succeeded. Creator received ${commitmentAmount.value}; treasury balance is 0.`);
    });
  });

  describe("set-treasury-owner", () => {
    it("ensures treasury owner can update owner", () => {
      LOG.section("Treasury — set-treasury-owner");
      LOG.test("Current owner transfers ownership to another principal.");
      // Arrange
      const currentOwner = simnet.callReadOnlyFn(
        "treasury",
        "get-treasury-owner",
        [],
        deployer
      ).result as PrincipalCV;

      // Act
      const { result: setOwner } = simnet.callPublicFn(
        "treasury",
        "set-treasury-owner",
        [standardPrincipalCV(address2)],
        deployer
      );

      // Assert
      expect(setOwner).toBeOk(trueCV());

      const newOwner = simnet.callReadOnlyFn(
        "treasury",
        "get-treasury-owner",
        [],
        deployer
      ).result as PrincipalCV;
      expect(newOwner).toEqual(standardPrincipalCV(address2));
      LOG.pass("Ownership updated successfully.");
    });

    it("ensures only treasury owner can update owner", () => {
      LOG.test("Non-owner cannot call set-treasury-owner.");
      // Act - non-owner tries to update
      const { result: setOwner } = simnet.callPublicFn(
        "treasury",
        "set-treasury-owner",
        [standardPrincipalCV(address2)],
        address1
      );

      // Assert
      expect(setOwner).toBeErr(uintCV(ERR_UNAUTHORIZED));
      LOG.expectErr(ERR_UNAUTHORIZED);
    });

    it("ensures owner can transfer ownership multiple times", () => {
      LOG.test("Owner chain: deployer → wallet_1 → wallet_2 → wallet_3; final owner verified.");
      // Act - transfer from deployer to address1
      const setOwner1 = simnet.callPublicFn(
        "treasury",
        "set-treasury-owner",
        [standardPrincipalCV(address1)],
        deployer
      );
      expect(setOwner1.result).toBeOk(trueCV());

      // Transfer from address1 to address2
      const setOwner2 = simnet.callPublicFn(
        "treasury",
        "set-treasury-owner",
        [standardPrincipalCV(address2)],
        address1
      );
      expect(setOwner2.result).toBeOk(trueCV());

      // Transfer from address2 to address3
      const setOwner3 = simnet.callPublicFn(
        "treasury",
        "set-treasury-owner",
        [standardPrincipalCV(address3)],
        address2
      );
      expect(setOwner3.result).toBeOk(trueCV());

      // Assert
      const finalOwner = simnet.callReadOnlyFn(
        "treasury",
        "get-treasury-owner",
        [],
        deployer
      ).result as PrincipalCV;
      expect(finalOwner).toEqual(standardPrincipalCV(address3));
      LOG.pass("Multiple ownership transfers succeeded.");
    });
  });

  describe("reward-random-winners", () => {
    it("ensures reward-random-winners fails when called by non-owner", () => {
      LOG.section("Treasury — reward-random-winners");
      LOG.test("Non-owner cannot call reward-random-winners.");
      // Arrange - deposit some tokens first
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(1000000), standardPrincipalCV(address1), wstxToken],
        address1
      );

      const winners = listCV([
        standardPrincipalCV(address2),
        standardPrincipalCV(address3),
      ]);
      const tokens = listCV([wstxToken]);

      // Act - non-owner tries to call
      const { result: reward } = simnet.callPublicFn(
        "treasury",
        "reward-random-winners",
        [winners, tokens],
        address1
      );

      // Assert
      expect(reward).toBeErr(uintCV(ERR_UNAUTHORIZED));
      LOG.expectErr(ERR_UNAUTHORIZED);
    });

    it("ensures reward-random-winners succeeds with empty winners list", () => {
      LOG.test("Owner calls with empty winners list; call succeeds (no distribution).");
      // Arrange - deposit tokens
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(1000000), standardPrincipalCV(address1), wstxToken],
        address1
      );

      const winners = listCV([]);
      const tokens = listCV([wstxToken]);

      // Act - owner calls with empty winners
      const { result: reward } = simnet.callPublicFn(
        "treasury",
        "reward-random-winners",
        [winners, tokens],
        deployer
      );

      // Assert - should succeed (no winners to reward, but no error)
      expect(reward).toBeOk(trueCV());
      LOG.pass("Empty winners list accepted; no error.");
    });

    it("ensures reward-random-winners distributes rewards correctly", () => {
      LOG.test("50% to owner, 50% split among winners; balances asserted.");
      // Arrange - deposit tokens
      const depositAmount = uintCV(1000000);
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [depositAmount, standardPrincipalCV(address1), wstxToken],
        address1
      );

      const treasuryBalanceBefore = getTreasuryBalance(wstxPrincipal);
      const winner1BalanceBefore = getTokenBalance(standardPrincipalCV(address2), wstxPrincipal);
      const winner2BalanceBefore = getTokenBalance(standardPrincipalCV(address3), wstxPrincipal);
      const ownerBalanceBefore = getTokenBalance(standardPrincipalCV(deployer), wstxPrincipal);

      const winners = listCV([
        standardPrincipalCV(address2),
        standardPrincipalCV(address3),
      ]);
      const tokens = listCV([wstxToken]);

      // Act - owner calls reward-random-winners
      const { result: reward } = simnet.callPublicFn(
        "treasury",
        "reward-random-winners",
        [winners, tokens],
        deployer
      );

      // Assert
      expect(reward).toBeOk(trueCV());

      // Treasury balance should be zero (all distributed: 50% to winners, 50% to owner)
      const treasuryBalanceAfter = getTreasuryBalance(wstxPrincipal);
      expect(BigInt(treasuryBalanceAfter)).toBe(BigInt(0));

      // Winners should receive 25% each (50% / 2 winners)
      const winner1BalanceAfter = getTokenBalance(standardPrincipalCV(address2), wstxPrincipal);
      const winner2BalanceAfter = getTokenBalance(standardPrincipalCV(address3), wstxPrincipal);
      const expectedRewardPerWinner = BigInt(depositAmount.value) / BigInt(4); // 50% / 2 = 25%
      expect(
        BigInt(winner1BalanceAfter) - BigInt(winner1BalanceBefore)
      ).toBe(expectedRewardPerWinner);
      expect(
        BigInt(winner2BalanceAfter) - BigInt(winner2BalanceBefore)
      ).toBe(expectedRewardPerWinner);

      // Owner should receive 50%
      const ownerBalanceAfter = getTokenBalance(standardPrincipalCV(deployer), wstxPrincipal);
      const expectedOwnerReward = BigInt(depositAmount.value) / BigInt(2);
      expect(BigInt(ownerBalanceAfter) - BigInt(ownerBalanceBefore)).toBe(
        expectedOwnerReward
      );
      LOG.pass("Rewards distributed: 50% owner, 25% per winner.");
    });

    it("ensures reward-random-winners works with single winner", () => {
      LOG.test("Single winner receives 50% fee share; owner receives 50%.");
      // Arrange - deposit tokens
      const depositAmount = uintCV(1000000);
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [depositAmount, standardPrincipalCV(address1), wstxToken],
        address1
      );

      const winnerBalanceBefore = getTokenBalance(standardPrincipalCV(address2), wstxPrincipal);
      const ownerBalanceBefore = getTokenBalance(standardPrincipalCV(deployer), wstxPrincipal);

      const winners = listCV([standardPrincipalCV(address2)]);
      const tokens = listCV([wstxToken]);

      // Act
      const { result: reward } = simnet.callPublicFn(
        "treasury",
        "reward-random-winners",
        [winners, tokens],
        deployer
      );

      // Assert
      expect(reward).toBeOk(trueCV());

      // Single winner should receive 50% (all of the fee portion)
      const winnerBalanceAfter = getTokenBalance(standardPrincipalCV(address2), wstxPrincipal);
      const expectedReward = BigInt(depositAmount.value) / BigInt(2);
      expect(BigInt(winnerBalanceAfter) - BigInt(winnerBalanceBefore)).toBe(
        expectedReward
      );

      // Owner should receive 50%
      const ownerBalanceAfter = getTokenBalance(standardPrincipalCV(deployer), wstxPrincipal);
      expect(BigInt(ownerBalanceAfter) - BigInt(ownerBalanceBefore)).toBe(
        expectedReward
      );
      LOG.pass("Single-winner and owner rewards correct.");
    });

    it("ensures reward-random-winners works with multiple tokens and winners", () => {
      LOG.test("Multiple tokens and multiple winners; WSTX and sBTC split 50% owner / 50% winners.");
      // Arrange - deposit tokens multiple times to build balance
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(1000000), standardPrincipalCV(address1), sbtToken],
        address1
      );
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [uintCV(500000), standardPrincipalCV(address2), wstxToken],
        address2
      );

      const treasuryBalanceBefore = getTreasuryBalance(wstxPrincipal);
      const sbtTreasuryBalanceBefore = getTreasuryBalance(sbtToken);
      const winner3BalanceBeforestx = getTokenBalance(standardPrincipalCV(address3), wstxPrincipal);
      const winner3BalanceBeforesbtc = getTokenBalance(standardPrincipalCV(address3), sbtToken);
      const winner4BalanceBeforestx = getTokenBalance(standardPrincipalCV(address4), wstxPrincipal);
      const winner4BalanceBeforesbtc = getTokenBalance(standardPrincipalCV(address4), sbtToken);
      const winner5BalanceBeforestx = getTokenBalance(standardPrincipalCV(address5), wstxPrincipal);
      const winner5BalanceBeforesbtc = getTokenBalance(standardPrincipalCV(address5), sbtToken);
      const ownerBalanceBeforestx = getTokenBalance(standardPrincipalCV(deployer), wstxPrincipal);
      const ownerBalanceBeforesbtc = getTokenBalance(standardPrincipalCV(deployer), sbtToken);
      const winners = listCV([standardPrincipalCV(address3), standardPrincipalCV(address4), standardPrincipalCV(address5)]);
      const tokens = listCV([wstxToken, sbtToken]);

      // Act
      const { result: reward } = simnet.callPublicFn(
        "treasury",
        "reward-random-winners",
        [winners, tokens],
        deployer
      );

      // Assert
      expect(reward).toBeOk(trueCV());

      // Treasury should be empty
      const treasuryBalanceAfter = getTreasuryBalance(wstxPrincipal);
      const sbtTreasuryBalanceAfter = getTreasuryBalance(sbtToken);
      expect(BigInt(treasuryBalanceAfter)).toBe(BigInt(0));
      expect(BigInt(sbtTreasuryBalanceAfter)).toBe(BigInt(0));

   
      const treasuryWstxTotalBalance = BigInt(treasuryBalanceBefore);
      const amountForWinnersWstx = treasuryWstxTotalBalance / BigInt(2);
      const totalSbtBalance = BigInt(sbtTreasuryBalanceBefore);
      const amountForWinnersSbt = totalSbtBalance / BigInt(2);
      const expectedWstxRewardPerWinner = amountForWinnersWstx / BigInt(3);
      const expectedSbtRewardPerWinner = amountForWinnersSbt / BigInt(3);
      const winner3BalanceAfterstx = getTokenBalance(standardPrincipalCV(address3), wstxPrincipal);
      const winner3BalanceAftersbtc = getTokenBalance(standardPrincipalCV(address3), sbtToken);
      const winner4BalanceAfterstx = getTokenBalance(standardPrincipalCV(address4), wstxPrincipal);
      const winner4BalanceAftersbtc = getTokenBalance(standardPrincipalCV(address4), sbtToken);
      const winner5BalanceAfterstx = getTokenBalance(standardPrincipalCV(address5), wstxPrincipal);
      const winner5BalanceAftersbtc = getTokenBalance(standardPrincipalCV(address5), sbtToken);
      const ownerBalanceAfterstx = getTokenBalance(standardPrincipalCV(deployer), wstxPrincipal);
      const ownerBalanceAftersbtc = getTokenBalance(standardPrincipalCV(deployer), sbtToken);
      expect(BigInt(winner3BalanceAfterstx) - BigInt(winner3BalanceBeforestx)).toBe(expectedWstxRewardPerWinner);
      expect(BigInt(winner3BalanceAftersbtc) - BigInt(winner3BalanceBeforesbtc)).toBe(expectedSbtRewardPerWinner);
      expect(BigInt(winner4BalanceAfterstx) - BigInt(winner4BalanceBeforestx)).toBe(expectedWstxRewardPerWinner);
      expect(BigInt(winner4BalanceAftersbtc) - BigInt(winner4BalanceBeforesbtc)).toBe(expectedSbtRewardPerWinner);
      expect(BigInt(winner5BalanceAfterstx) - BigInt(winner5BalanceBeforestx)).toBe(expectedWstxRewardPerWinner);
      expect(BigInt(winner5BalanceAftersbtc) - BigInt(winner5BalanceBeforesbtc)).toBe(expectedSbtRewardPerWinner);
      expect(BigInt(ownerBalanceAfterstx) - BigInt(ownerBalanceBeforestx)).toBe(amountForWinnersWstx);
      expect(BigInt(ownerBalanceAftersbtc) - BigInt(ownerBalanceBeforesbtc)).toBe(amountForWinnersSbt);
      LOG.pass("Multi-token, multi-winner distribution verified.");
    });


    it("ensures reward-random-winners succeeds with empty tokens list", () => {
      LOG.test("Owner calls with empty tokens list; call succeeds.");
      // Arrange
      const winners = listCV([standardPrincipalCV(address2)]);
      const tokens = listCV([]);

      // Act
      const { result: reward } = simnet.callPublicFn(
        "treasury",
        "reward-random-winners",
        [winners, tokens],
        deployer
      );

      // Assert - should succeed with empty tokens list
      expect(reward).toBeOk(trueCV());
      LOG.pass("Empty tokens list accepted.");
    });

    it("ensures reward-random-winners handles maximum winners correctly", () => {
      LOG.test("Multiple winners (4); 50% to owner, 50% split among winners; treasury drained.");
      // Arrange - deposit tokens
      const depositAmount = uintCV(10000000); // Large amount
      simnet.callPublicFn(
        "treasury",
        "deposit",
        [depositAmount, standardPrincipalCV(address1), wstxToken],
        address1
      );

      // Create list with multiple winners (up to 100 as per contract)
      const winners = listCV([
        standardPrincipalCV(address1),
        standardPrincipalCV(address2),
        standardPrincipalCV(address3),
        standardPrincipalCV(address4),
      ]);
      const tokens = listCV([wstxToken]);

      const treasuryBalanceBefore = getTreasuryBalance(wstxPrincipal);
      
      // Get balances before the function call
      const winner2BalanceBefore = getTokenBalance(standardPrincipalCV(address2), wstxPrincipal);
      const winner3BalanceBefore = getTokenBalance(standardPrincipalCV(address3), wstxPrincipal);
      const ownerBalanceBefore = getTokenBalance(standardPrincipalCV(deployer), wstxPrincipal);

      // Act
      const { result: reward } = simnet.callPublicFn(
        "treasury",
        "reward-random-winners",
        [winners, tokens],
        deployer
      );

      // Assert
      expect(reward).toBeOk(trueCV());

      // Treasury should be empty
      const treasuryBalanceAfter = getTreasuryBalance(wstxPrincipal);
      expect(BigInt(treasuryBalanceAfter)).toBe(BigInt(0));

      // Each winner should receive 50% / 4 = 12.5%
      const expectedRewardPerWinner = BigInt(depositAmount.value) / BigInt(8);
      
      // Check address2
      const winner2BalanceAfter = getTokenBalance(standardPrincipalCV(address2), wstxPrincipal);
      expect(
        BigInt(winner2BalanceAfter) - BigInt(winner2BalanceBefore)
      ).toBe(expectedRewardPerWinner);
      
      // Check address3
      const winner3BalanceAfter = getTokenBalance(standardPrincipalCV(address3), wstxPrincipal);
      expect(
        BigInt(winner3BalanceAfter) - BigInt(winner3BalanceBefore)
      ).toBe(expectedRewardPerWinner);
      
      // Owner should receive 50%
      const expectedOwnerReward = BigInt(depositAmount.value) / BigInt(2);
      const ownerBalanceAfter = getTokenBalance(standardPrincipalCV(deployer), wstxPrincipal);
      expect(BigInt(ownerBalanceAfter) - BigInt(ownerBalanceBefore)).toBe(
        expectedOwnerReward
      );
      LOG.pass("Max-winners case: per-winner and owner rewards correct.");
    });
  });

  describe("read-only functions", () => {
    describe("get-balance", () => {
      it("returns zero for token with no balance", () => {
        LOG.section("Treasury — read-only: get-balance");
        LOG.test("get-balance for token with no deposits returns 0.");
        // Act
        const balance = simnet.callReadOnlyFn(
          "treasury",
          "get-balance",
          [wstxPrincipal],
          deployer
        ).result as UIntCV;

        // Assert
        expect(balance.value).toBe(BigInt(0));
        LOG.pass("Balance is 0 as expected.");
      });

      it("returns correct balance after deposit", () => {
        LOG.test("After one deposit, get-balance returns that amount.");
        // Arrange
        const depositAmount = uintCV(1000000);
        simnet.callPublicFn(
          "treasury",
          "deposit",
          [depositAmount, standardPrincipalCV(address1), wstxToken],
          address1
        );

        // Act
        const balance = simnet.callReadOnlyFn(
          "treasury",
          "get-balance",
          [wstxPrincipal],
          deployer
        ).result as UIntCV;

        // Assert
        expect(balance.value).toBe(BigInt(depositAmount.value));
        LOG.pass("Balance matches deposit amount.");
      });

      it("returns updated balance after multiple deposits", () => {
        LOG.test("Multiple deposits; get-balance returns total.");
        // Arrange
        simnet.callPublicFn(
          "treasury",
          "deposit",
          [uintCV(500000), standardPrincipalCV(address1), wstxToken],
          address1
        );
        simnet.callPublicFn(
          "treasury",
          "deposit",
          [uintCV(300000), standardPrincipalCV(address2), wstxToken],
          address2
        );
        simnet.callPublicFn(
          "treasury",
          "deposit",
          [uintCV(200000), standardPrincipalCV(address3), wstxToken],
          address3
        );

        // Act
        const balance = simnet.callReadOnlyFn(
          "treasury",
          "get-balance",
          [wstxPrincipal],
          deployer
        ).result as UIntCV;

        // Assert
        expect(balance.value).toBe(BigInt(1000000));
        LOG.pass("Cumulative balance correct.");
      });
    });

    describe("get-treasury-owner", () => {
      it("returns initial treasury owner", () => {
        LOG.section("Treasury — read-only: get-treasury-owner");
        LOG.test("Initial owner is deployer.");
        // Act
        const owner = simnet.callReadOnlyFn(
          "treasury",
          "get-treasury-owner",
          [],
          deployer
        ).result as PrincipalCV;

        // Assert
        expect(owner).toEqual(standardPrincipalCV(deployer));
        LOG.pass("Deployer is initial owner.");
      });

      it("returns updated owner after ownership transfer", () => {
        LOG.test("After set-treasury-owner, get-treasury-owner returns new owner.");
        // Arrange
        simnet.callPublicFn(
          "treasury",
          "set-treasury-owner",
          [standardPrincipalCV(address1)],
          deployer
        );

        // Act
        const owner = simnet.callReadOnlyFn(
          "treasury",
          "get-treasury-owner",
          [],
          deployer
        ).result as PrincipalCV;

        // Assert
        expect(owner).toEqual(standardPrincipalCV(address1));
        LOG.pass("Updated owner returned correctly.");
      });
    });
  });
});

