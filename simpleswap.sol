// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// SimpleSwap - Un contrato basico tipo DEX para intercambiar tokens y gestionar liquidez
/// Este contrato replica la logica principal de Uniswap sin usar su protocolo

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
}

/// Informacion de liquidez para cada par de tokens
struct Pool {
    uint reserveA;
    uint reserveB;
    uint totalLiquidity;
    mapping(address => uint) liquidity;
}

contract SimpleSwap {
    /// Mapeo de clave (hash de tokenA y tokenB) a su pool
    mapping(bytes32 => Pool) private pools;

    /// Retorna la clave del pool sin importar el orden de los tokens
    function _getPoolKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return tokenA < tokenB
            ? keccak256(abi.encodePacked(tokenA, tokenB))
            : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    /// Agrega liquidez a un pool
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
        require(block.timestamp <= deadline, "Transaccion expirada");

        bytes32 poolKey = _getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[poolKey];

        // Transferir tokens del usuario al contrato
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        // Inicializa reservas si es el primer proveedor de liquidez
        if (pool.totalLiquidity == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            // Calcula la proporcion requerida entre tokens
            amountA = (amountBDesired * pool.reserveA) / pool.reserveB;
            require(amountA <= amountADesired, "Se requiere demasiado A");

            amountB = (amountADesired * pool.reserveB) / pool.reserveA;
            require(amountB <= amountBDesired, "Se requiere demasiado B");
        }

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage demasiado alto");

        // Actualiza reservas
        pool.reserveA += amountA;
        pool.reserveB += amountB;

        // Emite tokens de liquidez
        liquidity = amountA + amountB;
        pool.totalLiquidity += liquidity;
        pool.liquidity[to] += liquidity;
    }

    /// Quita liquidez y devuelve los tokens al usuario
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        require(block.timestamp <= deadline, "Transaccion expirada");

        bytes32 poolKey = _getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[poolKey];

        require(pool.liquidity[msg.sender] >= liquidity, "Liquidez insuficiente");

        // Calcula la proporcion de tokens que le corresponde al usuario
        amountA = (liquidity * pool.reserveA) / pool.totalLiquidity;
        amountB = (liquidity * pool.reserveB) / pool.totalLiquidity;

        require(amountA >= amountAMin && amountB >= amountBMin, "Slippage demasiado alto");

        // Actualiza reservas
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        pool.liquidity[msg.sender] -= liquidity;
        pool.totalLiquidity -= liquidity;

        // Transfiere los tokens al usuario
        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);
    }

    /// Intercambia una cantidad exacta de tokenIn por tokenOut
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path.length == 2, "Solo se permite swap directo");
        require(block.timestamp <= deadline, "Transaccion expirada");

        address tokenIn = path[0];
        address tokenOut = path[1];
        bytes32 poolKey = _getPoolKey(tokenIn, tokenOut);
        Pool storage pool = pools[poolKey];

        // Transferir token de entrada al contrato
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Determinar reservas
        uint reserveIn = tokenIn < tokenOut ? pool.reserveA : pool.reserveB;
        uint reserveOut = tokenIn < tokenOut ? pool.reserveB : pool.reserveA;

        // Calcular cantidad de salida
        uint amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Slippage demasiado alto");

        // Actualizar reservas segun el orden
        if (tokenIn < tokenOut) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += amountIn;
            pool.reserveA -= amountOut;
        }

        // Transferir token de salida al destinatario
        IERC20(tokenOut).transfer(to, amountOut);

        // Registrar los montos intercambiados
        //amounts = new uint ;
        amounts[0] = amountIn;
        amounts[1] = amountOut;
        return amounts;
    }

    /// Devuelve el precio de tokenA en terminos de tokenB
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        bytes32 poolKey = _getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[poolKey];

        uint reserveA = tokenA < tokenB ? pool.reserveA : pool.reserveB;
        uint reserveB = tokenA < tokenB ? pool.reserveB : pool.reserveA;

        require(reserveB != 0, "Division por cero");
        price = (reserveA * 1e18) / reserveB; // Escalado para precision
    }

    /// Calcula cuantos tokens se recibiran al intercambiar
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) public pure returns (uint amountOut) {
        require(reserveIn > 0 && reserveOut > 0, "Liquidez insuficiente");
        uint amountInWithFee = amountIn * 997; // Aplica comision del 0.3%
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
