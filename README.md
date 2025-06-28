# 🦄 SimpleSwap

**SimpleSwap** es un contrato inteligente escrito en Solidity que replica la funcionalidad básica de Uniswap sin depender de su protocolo. Permite agregar/remover liquidez, intercambiar tokens, obtener precios y calcular montos de intercambio utilizando tokens ERC-20.

## 📌 Características principales

- ✅ Agregar liquidez (Add Liquidity)
- ✅ Remover liquidez (Remove Liquidity)
- ✅ Intercambiar tokens (Swap)
- ✅ Obtener el precio de un token en términos de otro
- ✅ Calcular cuánto recibirías por un intercambio

---

## ⚙️ Funciones

### 1. `addLiquidity(...)`

Agrega tokens a un pool y recibe tokens de liquidez.

```solidity
function addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
) external returns (uint amountA, uint amountB, uint liquidity);
