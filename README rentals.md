### Installation

From a fresh Qbox build
1. Remove `qbx_apartments`
2. Remove `qbx_houses`
3. Either use no spawn system (so the core defaults to last location) or https://github.com/Qbox-project/qbx_spawn/

### Rental System for New Players

This resource now includes a rental system for new characters who don't have apartments. Here's how it works:

#### Features:
- **Rental Apartments**: New players can now rent apartments instead of getting them for free
- **Weekly Rent**: Rent is automatically deducted from the player's bank account every week
- **Money Checks**: Players must have sufficient funds in their bank account to rent
- **One Rental Per Player**: Players can only have one rental property at a time
- **Admin Commands**: Server administrators can create rental properties for existing players

#### Configuration:
The rental system can be configured in `config/shared.lua`:

```lua
rentalConfig = {
    enabled = true, -- Enable rental system for new players
    defaultRentInterval = 168, -- 7 days in hours
    defaultRentPrice = 500, -- Default rent price per interval
    maxRentalsPerPlayer = 1, -- Maximum rentals a new player can have
}
```

#### Apartment Configuration:
Each apartment in `apartmentOptions` can be configured for rental:

```lua
{
    interior = 'DellPerroHeightsApt4',
    label = 'Del Perro Heights Apt',
    description = 'Enjoy ocean views far away from tourists and bums on Del Perro Beach.',
    enter = vec3(-1447.35, -537.84, 34.74),
    rentable = true, -- Make this apartment rentable
    rentPrice = 400, -- Weekly rent price
    rentInterval = 168 -- 7 days in hours
}
```

#### Admin Commands:
- `/createrental [player_id] [apartment_index]` - Create a rental property for an existing player (Admin only)

#### How It Works:
1. When a new player joins and doesn't have an apartment, they'll see the apartment selection screen
2. Apartments marked as `rentable = true` will show rental information and prices
3. Players must confirm they want to rent and have sufficient funds
4. The first rent payment is deducted immediately
5. Rent continues to be deducted automatically every week
6. If a player can't pay rent, they lose the property

### todo

- Realtor job. Simple command to make more properties. (steal more code from Tony)
- Add more stuff to decoration options, i think Izzy is working on it, ask her.
- Add support for more garages
- Proper NUI for managing realtor job, instead of just using ox_lib context menu.