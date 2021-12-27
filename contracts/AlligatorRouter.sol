// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.6.12;

import "./libraries/AlligatorLibrary.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IAlligatorRouter.sol";
import "./operations/interfaces/IAlligatorFactory.sol";
import "./interfaces/IERC20Alligator.sol";
import "./interfaces/IWAVAX.sol";

contract AlligatorRouter is IAlligatorRouter {
    using SafeMath for uint256;

    address public immutable override factory;
    address public immutable override WAVAX;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "AlligatorRouter: EXPIRED");
        _;
    }

    constructor(address _factory, address _WAVAX) public {
        factory = _factory;
        WAVAX = _WAVAX;
    }

    receive() external payable {
        assert(msg.sender == WAVAX); // only accept AVAX via fallback from the WAVAX contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IAlligatorFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IAlligatorFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = AlligatorLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = AlligatorLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "AlligatorRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = AlligatorLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "AlligatorRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = AlligatorLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IAlligatorPair(pair).mint(to);
    }

    function addLiquidityAVAX(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountAVAXMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountAVAX,
            uint256 liquidity
        )
    {
        (amountToken, amountAVAX) = _addLiquidity(
            token,
            WAVAX,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountAVAXMin
        );
        address pair = AlligatorLibrary.pairFor(factory, token, WAVAX);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWAVAX(WAVAX).deposit{value: amountAVAX}();
        assert(IWAVAX(WAVAX).transfer(pair, amountAVAX));
        liquidity = IAlligatorPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountAVAX) TransferHelper.safeTransferAVAX(msg.sender, msg.value - amountAVAX);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = AlligatorLibrary.pairFor(factory, tokenA, tokenB);
        IAlligatorPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IAlligatorPair(pair).burn(to);
        (address token0, ) = AlligatorLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "AlligatorRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "AlligatorRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityAVAX(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountAVAXMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountAVAX) {
        (amountToken, amountAVAX) = removeLiquidity(
            token,
            WAVAX,
            liquidity,
            amountTokenMin,
            amountAVAXMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWAVAX(WAVAX).withdraw(amountAVAX);
        TransferHelper.safeTransferAVAX(to, amountAVAX);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = AlligatorLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IAlligatorPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityAVAXWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountAVAXMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountAVAX) {
        address pair = AlligatorLibrary.pairFor(factory, token, WAVAX);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IAlligatorPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountAVAX) = removeLiquidityAVAX(token, liquidity, amountTokenMin, amountAVAXMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityAVAXSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountAVAXMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountAVAX) {
        (, amountAVAX) = removeLiquidity(
            token,
            WAVAX,
            liquidity,
            amountTokenMin,
            amountAVAXMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20Alligator(token).balanceOf(address(this)));
        IWAVAX(WAVAX).withdraw(amountAVAX);
        TransferHelper.safeTransferAVAX(to, amountAVAX);
    }

    function removeLiquidityAVAXWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountAVAXMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountAVAX) {
        address pair = AlligatorLibrary.pairFor(factory, token, WAVAX);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IAlligatorPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountAVAX = removeLiquidityAVAXSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountAVAXMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = AlligatorLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? AlligatorLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IAlligatorPair(AlligatorLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = AlligatorLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "AlligatorRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            AlligatorLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = AlligatorLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "AlligatorRouter: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            AlligatorLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactAVAXForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WAVAX, "AlligatorRouter: INVALID_PATH");
        amounts = AlligatorLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "AlligatorRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IWAVAX(WAVAX).deposit{value: amounts[0]}();
        assert(IWAVAX(WAVAX).transfer(AlligatorLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactAVAX(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WAVAX, "AlligatorRouter: INVALID_PATH");
        amounts = AlligatorLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "AlligatorRouter: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            AlligatorLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWAVAX(WAVAX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferAVAX(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForAVAX(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WAVAX, "AlligatorRouter: INVALID_PATH");
        amounts = AlligatorLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "AlligatorRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            AlligatorLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWAVAX(WAVAX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferAVAX(to, amounts[amounts.length - 1]);
    }

    function swapAVAXForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WAVAX, "AlligatorRouter: INVALID_PATH");
        amounts = AlligatorLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "AlligatorRouter: EXCESSIVE_INPUT_AMOUNT");
        IWAVAX(WAVAX).deposit{value: amounts[0]}();
        assert(IWAVAX(WAVAX).transfer(AlligatorLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferAVAX(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = AlligatorLibrary.sortTokens(input, output);
            IAlligatorPair pair = IAlligatorPair(AlligatorLibrary.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = IERC20Alligator(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = AlligatorLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? AlligatorLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            AlligatorLibrary.pairFor(factory, path[0], path[1]),
            amountIn
        );
        uint256 balanceBefore = IERC20Alligator(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20Alligator(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            "AlligatorRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactAVAXForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        require(path[0] == WAVAX, "AlligatorRouter: INVALID_PATH");
        uint256 amountIn = msg.value;
        IWAVAX(WAVAX).deposit{value: amountIn}();
        assert(IWAVAX(WAVAX).transfer(AlligatorLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20Alligator(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20Alligator(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            "AlligatorRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactTokensForAVAXSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WAVAX, "AlligatorRouter: INVALID_PATH");
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            AlligatorLibrary.pairFor(factory, path[0], path[1]),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20Alligator(WAVAX).balanceOf(address(this));
        require(amountOut >= amountOutMin, "AlligatorRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IWAVAX(WAVAX).withdraw(amountOut);
        TransferHelper.safeTransferAVAX(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return AlligatorLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return AlligatorLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return AlligatorLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return AlligatorLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return AlligatorLibrary.getAmountsIn(factory, amountOut, path);
    }
}
