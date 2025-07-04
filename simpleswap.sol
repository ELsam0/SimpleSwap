// SPDX-License-Identifier: MIT
pragma solidity   ^0.8.30;

/// @title SimpleSwap
/// @author Samuel garate
/// @notice Este contrato permite agregar liquidez, intercambiar tokens y consultar precios, simulando un DEX básico.

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
}

/// @dev Estructura para guardar reservas y liquidez por usuario en un par
struct Pool {
    uint reserveA;
    uint reserveB;
    uint totalLiquidity;
    mapping(address => uint) liquidity;
}

contract SimpleSwap {
    /// @dev Mapea la combinación tokenA-tokenB a su pool
    mapping(bytes32 => Pool) private pools;

    /// Eventos
    event LiquidityAdded(address indexed provider, address tokenA, address tokenB, uint amountA, uint amountB, uint liquidity);
    event LiquidityRemoved(address indexed provider, address tokenA, address tokenB, uint amountA, uint amountB);
    event TokenSwapped(address indexed user, address tokenIn, address tokenOut, uint amountIn, uint amountOut);

    /// @dev Genera una clave hash única para cada combinación de tokens (orden independiente)
    function _getPoolKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return tokenA < tokenB
            ? keccak256(abi.encodePacked(tokenA, tokenB))
            : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    /// @notice Agrega liquidez a un pool
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        require(tokenA != tokenB, "Los tokens deben ser diferentes");
        require(to != address(0), "Direccion destinatario invalida");
        require(block.timestamp <= deadline, "Transaccion expirada");

        bytes32 poolKey = _getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[poolKey];

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        if (pool.totalLiquidity == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            amountA = (amountBDesired * pool.reserveA) / pool.reserveB;
            require(amountA <= amountADesired, "Se requiere demasiado A");

            amountB = (amountADesired * pool.reserveB) / pool.reserveA;
            require(amountB <= amountBDesired, "Se requiere demasiado B");
        }

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage demasiado alto");

        pool.reserveA += amountA;
        pool.reserveB += amountB;

        liquidity = amountA + amountB;
        pool.totalLiquidity += liquidity;
        pool.liquidity[to] += liquidity;

        emit LiquidityAdded(to, tokenA, tokenB, amountA, amountB, liquidity);
    }

    /// @notice Quita liquidez del pool
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        require(tokenA != tokenB, "Los tokens deben ser diferentes");
        require(to != address(0), "Direccion destinatario invalida");
        require(block.timestamp <= deadline, "Transaccion expirada");

        bytes32 poolKey = _getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[poolKey];

        require(pool.liquidity[msg.sender] >= liquidity, "Liquidez insuficiente");

        amountA = (liquidity * pool.reserveA) / pool.totalLiquidity;
        amountB = (liquidity * pool.reserveB) / pool.totalLiquidity;

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage demasiado alto");

        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        pool.liquidity[msg.sender] -= liquidity;
        pool.totalLiquidity -= liquidity;

        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);

        emit LiquidityRemoved(to, tokenA, tokenB, amountA, amountB);
    }

    /// @notice Intercambia una cantidad exacta de tokenIn por tokenOut
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path.length == 2, "Solo se permite swap directo");
        require(block.timestamp <= deadline, "Transaccion expirada");
        require(to != address(0), "Direccion invalida");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        bytes32 key = _getPoolKey(path[0], path[1]);
        Pool storage p = pools[key];

        uint reserveIn = path[0] < path[1] ? p.reserveA : p.reserveB;
        uint reserveOut = path[0] < path[1] ? p.reserveB : p.reserveA;

        uint amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Slippage alto");

        if (path[0] < path[1]) {
            p.reserveA += amountIn;
            p.reserveB -= amountOut;
        } else {
            p.reserveB += amountIn;
            p.reserveA -= amountOut;
        }

        IERC20(path[1]).transfer(to, amountOut);

        emit TokenSwapped(msg.sender, path[0], path[1], amountIn, amountOut);

        amounts = new uint[](2) ;
        amounts[0] = amountIn;
        amounts[1] = amountOut;
        return amounts;
    }

 
    /// @notice Devuelve el precio de tokenA en términos de tokenB
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        bytes32 poolKey = _getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[poolKey];

        uint reserveA = tokenA < tokenB ? pool.reserveA : pool.reserveB;
        uint reserveB = tokenA < tokenB ? pool.reserveB : pool.reserveA;

        require(reserveB != 0, "Division por cero");
        price = (reserveA * 1e18) / reserveB;
    }

    /// @notice Calcula cuántos tokens se recibirán al intercambiar
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) public pure returns (uint amountOut) {
        require(reserveIn > 0 && reserveOut > 0, "Liquidez insuficiente");
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Devuelve las reservas del par de tokens
    function getReserves(address tokenA, address tokenB) external view returns (uint reserveA, uint reserveB) {
        bytes32 poolKey = _getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[poolKey];
        reserveA = pool.reserveA;
        reserveB = pool.reserveB;
    }
}
