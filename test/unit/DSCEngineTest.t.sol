//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DeployDSSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Test,console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "test/mocks/MockFailedMintDSC.sol";

import {MockMoreDebtDSC} from "test/mocks/MockMoreDebtDSC.sol";
import {MockFailedTransfer} from "test/mocks/MockFailedTransfer.sol";
import {MockFailedTransferFrom} from "test/mocks/MockFailedTransferFrom.sol";

contract DSCEngineTest is StdCheats,Test {
    event CollateralRedeemed(address indexed redeemFrom,address indexed redeemTo,address token,uint256 amount);

    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;    
    uint256 public deployerKey;

    uint256 amountCollatateral =10 ether;
    uint256 amountToMint= 100 ether;
    address public user = address(1);

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;


    function setUp() external{
        DeployDSSC deployer = new DeployDSSC();
        (dsc,dsce,helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        if(block.chainid == 31_337){
            vm.deal(user,STARTING_USER_BALANCE);
        }

        ERC20Mock(weth).mint(user,STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user,STARTING_USER_BALANCE);

    } 

    //construcot Test//

    address[] public tokenAddresses;
    address[] public feedAddresses;

    function testRevertsIfTokenLengthIsNotEqualFeedLength() public{
       tokenAddresses.push(weth);
         feedAddresses.push(ethUsdPriceFeed);
            feedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedLengthMismatch.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));

    }
   ///price test//

    function testGetTokenAmountFromUsd() public {
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(weth,100 ether);
        assertEq(amountWeth,expectedWeth);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30_000e18;
        uint256 usdValue = dsce.getUsdValue(weth,ethAmount);
        assertEq(usdValue,expectedUsd);
    }

    ///depositCollateral test//
    function testRevertsIfTransferFromFails() public{
        address owner =  msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        feedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);    
        DSCEngine engine = new DSCEngine(tokenAddresses,feedAddresses,address(mockDsc));
        mockDsc.mint(user,amountCollatateral);

        vm.prank(owner);
        mockDsc.transferOwnership(address(engine));
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(engine),amountCollatateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        engine.depositCollateral(address(mockDsc),amountCollatateral);
        vm.stopPrank();
    }


    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollatateral);
        vm.expectRevert(DSCEngine.amountMustBeMoreThanZero.selector);
        dsce.depositCollateral(weth,0);
        vm.stopPrank();

    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAND","RAND",user,100e18);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotSupported.selector,address(randToken)));
        dsce.depositCollateral(address(randToken),amountCollatateral);
        vm.stopPrank();

    }

    modifier depositedCollateral(){
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollatateral);
        dsce.depositCollateral(weth,amountCollatateral);
        vm.stopPrank();
        _;
    }

    function testCanDeposiCollateralWithoutMinting() public depositedCollateral{
      uint256 userBalance = dsc.balanceOf(user);
      assertEq(userBalance,0);
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral{
        (uint256 totalDscMinted, uint256 collateralInUsd) = dsce.getAccountInformation(user);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth,collateralInUsd);
        assertEq(totalDscMinted,0);
        assertEq(expectedDepositedAmount,amountCollatateral);
    }

    //deposiCollaateralMintDSC test//

 modifier depositedCollateralAndMintedDsc(){
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce),amountCollatateral);
    dsce.depositCollateralAndMintDsc(weth,amountCollatateral,amountToMint);
    vm.stopPrank();
    _;
 }

 function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc{
     uint256 userBalance = dsc.balanceOf(user);
     assertEq(userBalance,amountToMint);
 }


 //mintDSC Test//

 function testRevertsIfMintFails() public {
    MockFailedMintDSC mockDsc = new MockFailedMintDSC();
    tokenAddresses = [weth];
    feedAddresses = [ethUsdPriceFeed];
    address owner =  msg.sender;
    vm.prank(owner);
    DSCEngine engine = new DSCEngine(tokenAddresses,feedAddresses,address(mockDsc));    
    mockDsc.transferOwnership(address(engine));

    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce),amountCollatateral);
    vm.expectRevert(DSCEngine.DSCEngine_MintFailed.selector);
    engine.depositCollateralAndMintDsc(weth,amountCollatateral,amountToMint);
    vm.stopPrank();
 }

    function testRevertsIfMintAmountZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollatateral);
         dsce.depositCollateralAndMintDsc(weth,amountCollatateral,amountToMint);
        vm.expectRevert(DSCEngine.amountMustBeMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral{
        vm.prank(user);
        dsce.mintDsc(amountToMint);

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance,amountToMint);
    }

    //burn dsc test//

    function testRevertIfBurnAmountIsBroken() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollatateral);
        dsce.depositCollateralAndMintDsc(weth,amountCollatateral,amountToMint);
        vm.expectRevert(DSCEngine.amountMustBeMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();

    }

    function testCantBurnMoreThanUserHas() public{
        vm.prank(user); 
        vm.expectRevert();
        dsce.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc{
       vm.startPrank(user);
       dsc.approve(address(dsce),amountToMint);
         dsce.burnDsc(amountToMint);
         vm.stopPrank();
            uint256 userBalance = dsc.balanceOf(user);
            assertEq(userBalance,0);
    }

    //Redeem collatarel test//

    function testRevertsIfTransferFails() public {

        address owner= msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        feedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine engine = new DSCEngine(tokenAddresses,feedAddresses,address(mockDsc));
       mockDsc.mint(user,amountCollatateral);
        vm.prank(owner);
        mockDsc.transferOwnership(address(engine));
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(engine),amountCollatateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        engine.redeemCollateral(address(mockDsc),amountCollatateral);
        vm.stopPrank();
    }


    function testRevertIfReddemAmontIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollatateral);
        dsce.depositCollateral(weth,amountCollatateral);
        vm.expectRevert(DSCEngine.amountMustBeMoreThanZero.selector);
        dsce.redeemCollateral(weth,0);
        vm.stopPrank();
    }

    function testCanReddemCollateral() public depositedCollateral{
        vm.startPrank(user);
        dsce.redeemCollateral(weth,amountCollatateral);
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userBalance,amountCollatateral);
        vm.stopPrank();
    }


    //reddem collateral for DSC test//
    
    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc{
        vm.startPrank(user);
        dsc.approve(address(dsce),amountToMint);
        vm.expectRevert(DSCEngine.amountMustBeMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth,0,amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemmDepositedCollatarel() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollatateral);
        dsce.depositCollateralAndMintDsc(weth,amountCollatateral,amountToMint);
        dsc.approve(address(dsce),amountToMint);
        dsce.redeemCollateralForDsc(weth,amountCollatateral,amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance,0);
    }


    //liquidate test//

    function testMustImproveHealthFactorOnLiquidation() public {

        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        feedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine engine = new DSCEngine(tokenAddresses,feedAddresses,address(mockDsc));
        mockDsc.transferOwnership(address(engine));

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine),amountCollatateral);
        engine.depositCollateralAndMintDsc(weth,amountCollatateral,amountToMint);
        vm.stopPrank();

        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator,collateralToCover);


        vm.startPrank(liquidator);  
        ERC20Mock(weth).approve(address(engine),collateralToCover);
        uint256 debtToCover = 10 ether;
        engine.depositCollateralAndMintDsc(weth,collateralToCover,debtToCover);
        mockDsc.approve(address(engine),debtToCover);

        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        vm.expectRevert(DSCEngine.DSCEngine_HealthFactorNotImproved.selector);
        engine.liquidate(weth,user,debtToCover);
        vm.stopPrank();

    }


      modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollatateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollatateral, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(user);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(weth, user, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

       function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = dsce.getTokenAmountFromUsd(weth, amountToMint)
            + (dsce.getTokenAmountFromUsd(weth, amountToMint) / dsce.getLiquidationBonus());

        uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(weth, amountCollatateral) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(user);
        assertEq(userDscMinted, 0);
    }



}
