// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AlligatorToken.sol";

interface IRewarder {
    function onGtrReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (IERC20);
}

library BoringERC20 {
    bytes4 private constant SIG_SYMBOL = 0x95d89b41; // symbol()
    bytes4 private constant SIG_NAME = 0x06fdde03; // name()
    bytes4 private constant SIG_DECIMALS = 0x313ce567; // decimals()
    bytes4 private constant SIG_TRANSFER = 0xa9059cbb; // transfer(address,uint256)
    bytes4 private constant SIG_TRANSFER_FROM = 0x23b872dd; // transferFrom(address,address,uint256)

    function returnDataToString(bytes memory data) internal pure returns (string memory) {
        if (data.length >= 64) {
            return abi.decode(data, (string));
        } else if (data.length == 32) {
            uint8 i = 0;
            while (i < 32 && data[i] != 0) {
                i++;
            }
            bytes memory bytesArray = new bytes(i);
            for (i = 0; i < 32 && data[i] != 0; i++) {
                bytesArray[i] = data[i];
            }
            return string(bytesArray);
        } else {
            return "???";
        }
    }

    /// @notice Provides a safe ERC20.symbol version which returns '???' as fallback string.
    /// @param token The address of the ERC-20 token contract.
    /// @return (string) Token symbol.
    function safeSymbol(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(SIG_SYMBOL));
        return success ? returnDataToString(data) : "???";
    }

    /// @notice Provides a safe ERC20.name version which returns '???' as fallback string.
    /// @param token The address of the ERC-20 token contract.
    /// @return (string) Token name.
    function safeName(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(SIG_NAME));
        return success ? returnDataToString(data) : "???";
    }

    /// @notice Provides a safe ERC20.decimals version which returns '18' as fallback value.
    /// @param token The address of the ERC-20 token contract.
    /// @return (uint8) Token decimals.
    function safeDecimals(IERC20 token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(SIG_DECIMALS));
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    /// @notice Provides a safe ERC20.transfer version for different ERC-20 implementations.
    /// Reverts on a failed transfer.
    /// @param token The address of the ERC-20 token.
    /// @param to Transfer tokens to.
    /// @param amount The token amount.
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(SIG_TRANSFER, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "BoringERC20: Transfer failed");
    }

    /// @notice Provides a safe ERC20.transferFrom version for different ERC-20 implementations.
    /// Reverts on a failed transfer.
    /// @param token The address of the ERC-20 token.
    /// @param from Transfer tokens from.
    /// @param to Transfer tokens to.
    /// @param amount The token amount.
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(SIG_TRANSFER_FROM, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "BoringERC20: TransferFrom failed");
    }
}

// The AlligatorFarmer manages the distribution of reward tokens to holders of staked LP tokens.
// It rewards GTR tokens to holders of staked LP tokens and supports double rewards farms that can
// reward users with any ERC-20 token.
contract AlligatorFarmer is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using BoringERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has deposited.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // At any point in time, the amount of GTRs entitled to a user but
        // is pending to be distributed is:
        //
        //   pendingReward = (user.amount * pool.accGtrPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool, this is what happens:
        //   1. The pool's `accGtrPerShare` (and `lastRewardTimestamp`) gets updated.
        //   2. User receives the pending reward sent to their address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of the LP token contract.
        uint256 allocPoint; // Number of allocation points assigned to this pool. GTRs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that GTRs distribution occured.
        uint256 accGtrPerShare; // Accumulated GTRs per share, times 1e12. See below.
        IRewarder rewarder; // Address of the rewarder for double rewards farms.
    }

    // The Alligator token
    AlligatorToken public gtr;
    // Dev address.
    address public devAddr;
    // Treasury address.
    address public treasuryAddr;
    // Investor address.
    address public investorAddr;
    // GTR tokens created per second.
    uint256 public gtrPerSec;
    // Percentage of pool rewards that goes to the devs.
    uint256 public devPercent;
    // Percentage of pool rewards that goes to the treasury.
    uint256 public treasuryPercent;
    // Percentage of pool rewards that goes to the investor.
    uint256 public investorPercent;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Set of all LP tokens that have been added as pools
    EnumerableSet.AddressSet private lpTokens;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when GTR mining starts.
    uint256 public startTimestamp;

    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    event Add(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accGtrPerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetDevAddress(address indexed oldAddress, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 _gtrPerSec);

    constructor(
        AlligatorToken _gtr,
        address _devAddr,
        address _treasuryAddr,
        address _investorAddr,
        uint256 _gtrPerSec,
        uint256 _startTimestamp,
        uint256 _devPercent,
        uint256 _treasuryPercent,
        uint256 _investorPercent
    ) public {
        require(0 <= _devPercent && _devPercent <= 500, "constructor: invalid dev percent value");
        require(0 <= _treasuryPercent && _treasuryPercent <= 500, "constructor: invalid treasury percent value");
        require(0 <= _investorPercent && _investorPercent <= 500, "constructor: invalid investor percent value");
        require(_devPercent + _treasuryPercent + _investorPercent <= 500, "constructor: total percent over max");
        gtr = _gtr;
        devAddr = _devAddr;
        treasuryAddr = _treasuryAddr;
        investorAddr = _investorAddr;
        gtrPerSec = _gtrPerSec;
        startTimestamp = _startTimestamp;
        devPercent = _devPercent;
        treasuryPercent = _treasuryPercent;
        investorPercent = _investorPercent;
        totalAllocPoint = 0;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new LP to the farms. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be incorrect if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        IRewarder _rewarder
    ) public onlyOwner {
        require(
            Address.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "add: rewarder must be contract or zero"
        );
        require(!lpTokens.contains(address(_lpToken)), "add: LP already added");
        // Sanity check to ensure _lpToken is an ERC20 token
        _lpToken.balanceOf(address(this));
        // Sanity check if we add a rewarder
        if (address(_rewarder) != address(0)) {
            _rewarder.onGtrReward(address(0), 0);
        }

        massUpdatePools();

        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accGtrPerShare: 0,
                rewarder: _rewarder
            })
        );
        lpTokens.add(address(_lpToken));
        emit Add(poolInfo.length.sub(1), _allocPoint, _lpToken, _rewarder);
    }

    // Update the given pool's GTR allocation point and/or rewarder. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder _rewarder,
        bool overwrite
    ) public onlyOwner {
        require(
            Address.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "set: rewarder must be contract or zero"
        );

        massUpdatePools();

        PoolInfo memory pool = poolInfo[_pid];
        totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        pool.allocPoint = _allocPoint;

        if (overwrite) {
            _rewarder.onGtrReward(address(0), 0); // sanity check
            pool.rewarder = _rewarder;
        }

        poolInfo[_pid] = pool;

        emit Set(_pid, _allocPoint, overwrite ? _rewarder : pool.rewarder, overwrite);
    }

    // View function to see pending GTRs on the frontend.
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingGtr,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accGtrPerShare = pool.accGtrPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp.sub(pool.lastRewardTimestamp);
            uint256 lpPercent = 1000 - devPercent - treasuryPercent - investorPercent;
            uint256 gtrReward = multiplier
                .mul(gtrPerSec)
                .mul(pool.allocPoint)
                .div(totalAllocPoint)
                .mul(lpPercent)
                .div(1000);
            accGtrPerShare = accGtrPerShare.add(gtrReward.mul(ACC_TOKEN_PRECISION).div(lpSupply));
        }
        pendingGtr = user.amount.mul(accGtrPerShare).div(ACC_TOKEN_PRECISION).sub(user.rewardDebt);

        // If it is a double reward farm, we return info about the bonus token as well.
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            bonusTokenSymbol = IERC20(pool.rewarder.rewardToken()).safeSymbol();
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 multiplier = block.timestamp.sub(pool.lastRewardTimestamp);
                uint256 gtrReward = multiplier.mul(gtrPerSec).mul(pool.allocPoint).div(totalAllocPoint);
                uint256 lpPercent = 1000 - devPercent - treasuryPercent - investorPercent;
                gtr.mint(devAddr, gtrReward.mul(devPercent).div(1000));
                gtr.mint(treasuryAddr, gtrReward.mul(treasuryPercent).div(1000));
                gtr.mint(investorAddr, gtrReward.mul(investorPercent).div(1000));
                gtr.mint(address(this), gtrReward.mul(lpPercent).div(1000));
                pool.accGtrPerShare = pool.accGtrPerShare.add(
                    gtrReward.mul(ACC_TOKEN_PRECISION).div(lpSupply).mul(lpPercent).div(1000)
                );
            }
            pool.lastRewardTimestamp = block.timestamp;
            poolInfo[_pid] = pool;
            emit UpdatePool(_pid, pool.lastRewardTimestamp, lpSupply, pool.accGtrPerShare);
        }
    }

    // Deposit LP tokens to AlligatorFarmer for GTR allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        updatePool(_pid);

        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount > 0) {
            // Harvest GTR
            uint256 pending = user.amount.mul(pool.accGtrPerShare).div(ACC_TOKEN_PRECISION).sub(user.rewardDebt);
            safeGtrTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }

        uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 receivedAmount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);

        user.amount = user.amount.add(receivedAmount);
        user.rewardDebt = user.amount.mul(pool.accGtrPerShare).div(ACC_TOKEN_PRECISION);

        IRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onGtrReward(msg.sender, user.amount);
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from AlligatorFarmer.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: amount too high");

        updatePool(_pid);

        if (user.amount > 0) {
            // Harvest GTR
            uint256 pending = user.amount.mul(pool.accGtrPerShare).div(ACC_TOKEN_PRECISION).sub(user.rewardDebt);
            safeGtrTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accGtrPerShare).div(ACC_TOKEN_PRECISION);

        IRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onGtrReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        IRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onGtrReward(msg.sender, 0);
        }

        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe GTR transfer function, just in case a rounding error causes the pool to not have enough GTRs.
    function safeGtrTransfer(address _to, uint256 _amount) internal {
        uint256 gtrBal = gtr.balanceOf(address(this));
        if (_amount > gtrBal) {
            gtr.transfer(_to, gtrBal);
        } else {
            gtr.transfer(_to, _amount);
        }
    }

    // Update the dev address.
    function dev(address _devAddr) public {
        require(msg.sender == devAddr, "dev: intruder alert");
        devAddr = _devAddr;
        emit SetDevAddress(msg.sender, _devAddr);
    }

    // Update treasury address by the previous treasury.
    function setTreasuryAddr(address _treasuryAddr) public {
        require(msg.sender == treasuryAddr, "setTreasuryAddr: intruder alert");
        treasuryAddr = _treasuryAddr;
    }

    // Update the investor address by the previous investor.
    function setInvestorAddr(address _investorAddr) public {
        require(msg.sender == investorAddr, "setInvestorAddr: intruder alert");
        investorAddr = _investorAddr;
    }
}
