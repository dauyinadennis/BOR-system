# Bitcoin Ordinal Rental System (BORS)

A smart contract system built on Stacks that enables secure renting of Bitcoin Ordinals with collateral-based protection.

## Overview

The Bitcoin Ordinal Rental System (BORS) is a decentralized platform that allows:
- Ordinal owners to list their Ordinals for rent
- Users to rent Ordinals by providing collateral
- Automated collateral management based on rental terms
- Reputation tracking for renters

## Key Features

- **Secure Rental Process**
  - Collateral-based security system
  - Automated payment processing
  - Built-in platform fee mechanism (2.5%)

- **Flexible Rental Terms**
  - Minimum rental period: 1 day (144 blocks)
  - Maximum rental period: 100 days (14400 blocks)
  - Extendable rental duration

- **User Protection**
  - Required collateral must exceed rental fee
  - Automatic collateral return for on-time returns
  - Collateral forfeiture for late returns

- **Reputation System**
  - Tracks completed and defaulted rentals
  - Reputation scores from 0-1000
  - +10 points for on-time returns
  - -50 points for late returns

## Core Functions

### For Ordinal Owners
- List Ordinals for rent with custom terms
- Set rental fee and required collateral
- Cancel listings (if not currently rented)
- Receive automatic payments

### For Renters
- Rent available Ordinals
- Extend active rentals
- Return Ordinals anytime before expiration
- Build reputation through responsible returns

### Platform Features
- Automated fee collection
- Emergency pause capability
- Transparent fee management
- User statistics tracking

## Security Features

- Emergency pause mechanism
- Collateral-based risk management
- Automated payment processing
- Owner-only administrative controls

## Technical Details

- Built on Clarity smart contracts
- Uses STX for payments and collateral
- Block-based timing system
- Event logging for key actions

## Administrative Functions

- Platform fee recipient management
- Fee withdrawal system
- Emergency pause toggle
- Platform statistics tracking

## Stats Tracking

The system maintains:
- Individual user statistics
- Platform-wide metrics
- Total rentals created
- Accumulated platform fees

---

## Note
This contract is implemented but requires frontend integration and thorough testing before deployment.