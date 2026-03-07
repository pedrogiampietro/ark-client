-- Item price table for balance tracker
-- supplyPrices: NPC buy price (what player pays to buy from NPC)
-- lootPrices: NPC sell price (what player gets selling to NPC)
-- Item IDs are client IDs (= server IDs for 7.72)

SUPPLY_PRICES = {
    -- Fluids
    [2006] = 80,  -- Vial (average of mana 100 + life 60) / fallback

    -- Runes (free rune shop)
    [2265] = 95,   -- Intense Healing Rune
    [2273] = 175,  -- Ultimate Healing Rune
    [2268] = 325,  -- Sudden Death Rune
    [2311] = 125,  -- Heavy Magic Missile
    [2304] = 180,  -- Great Fireball Rune
    [2287] = 40,   -- Light Magic Missile
    [2302] = 95,   -- Fireball Rune
    [2313] = 250,  -- Explosion Rune
    [2303] = 245,  -- Fire Wall Rune
    [2279] = 340,  -- Energy Wall Rune
    [2291] = 210,  -- Chameleon Rune
    [2305] = 235,  -- Firebomb Rune
    [2290] = 80,   -- Convince Creature Rune
    [2266] = 65,   -- Antidote Rune
    [2261] = 45,   -- Destroy Field Rune
    [2285] = 65,   -- Poison Field Rune
    [2301] = 85,   -- Fire Field Rune
    [2277] = 115,  -- Energy Field Rune
    [2289] = 210,  -- Poison Wall Rune
    [2260] = 10,   -- Blank Rune

    -- Premium runes
    [2292] = 130,  -- Envenom Rune
    [2310] = 80,   -- Desintegrate Rune
    [2286] = 170,  -- Poison Bomb Rune
    [2308] = 210,  -- Soulfire Rune
    [2262] = 325,  -- Energy Bomb Rune
    [2293] = 350,  -- Magic Wall Rune
    [2316] = 375,  -- Animate Dead Rune
    [2278] = 700,  -- Paralyze Rune
}

LOOT_PRICES = {
    -- Currency
    [2148] = 1,     -- Gold Coin
    [2152] = 100,   -- Platinum Coin
    [2160] = 10000, -- Crystal Coin

    -- Weapons
    [2379] = 2,     -- Dagger
    [2380] = 4,     -- Hand Axe
    [2389] = 3,     -- Spear
    [2384] = 5,     -- Rapier
    [2386] = 7,     -- Axe
    [2385] = 12,    -- Sabre
    [2376] = 25,    -- Sword
    [2398] = 30,    -- Mace
    [2417] = 120,   -- Battle Hammer
    [2378] = 80,    -- Battle Axe
    [2394] = 90,    -- Morning Star
    [2377] = 450,   -- Two Handed Sword
    [2381] = 400,   -- Halberd
    [2409] = 900,   -- Serpent Sword
    [2393] = 17000, -- Giant Sword
    [2434] = 2000,  -- Dragon Hammer
    [2430] = 2000,  -- Knight Axe
    [2436] = 6000,  -- Skull Staff
    [2419] = 150,   -- Scimitar
    [2411] = 50,    -- Poison Dagger
    [2432] = 10000, -- Fire Axe
    [2407] = 8000,  -- Bright Sword
    [2400] = 10000, -- Magic Longsword
    [2390] = 500,   -- Magic Plate Armor (Spear)
    [2423] = 6000,  -- Clerical Mace
    [2431] = 4000,  -- Stonecutter Axe

    -- Armor
    [2467] = 12,    -- Leather Armor
    [2464] = 70,    -- Chain Armor
    [2465] = 150,   -- Brass Armor
    [2463] = 400,   -- Plate Armor
    [2476] = 5000,  -- Knight Armor
    [2466] = 20000, -- Golden Armor
    [2489] = 400,   -- Dark Armor
    [2472] = 6400,  -- Magic Plate Armor
    [2487] = 900,   -- Crown Armor
    [2492] = 1200,  -- Dragon Scale Mail
    [2494] = 150,   -- Demon Armor
    [2475] = 5000,  -- Warrior Helmet

    -- Helmets
    [2461] = 4,     -- Leather Helmet
    [2458] = 17,    -- Chain Helmet
    [2460] = 30,    -- Brass Helmet
    [2473] = 66,    -- Viking Helmet
    [2459] = 145,   -- Iron Helmet
    [2457] = 190,   -- Steel Helmet
    [2490] = 250,   -- Dark Helmet
    [2462] = 450,   -- Devil Helmet
    [2479] = 500,   -- Strange Helmet
    [2663] = 150,   -- Mystic Turban
    [2471] = 12000, -- Golden Helmet
    [2491] = 2500,  -- Crown Helmet
    [2498] = 3000,  -- Royal Helmet

    -- Legs
    [2648] = 25,    -- Chain Legs
    [2477] = 5000,  -- Knight Legs
    [2488] = 1200,  -- Crown Legs
    [2470] = 30000, -- Golden Legs
    [2647] = 1000,  -- Plate Legs

    -- Boots
    [2643] = 2,     -- Leather Boots
    [2195] = 3000,  -- Boots of Haste
    [2645] = 10000, -- Steel Boots

    -- Shields
    [2512] = 5,     -- Wooden Shield
    [2511] = 16,    -- Brass Shield
    [2510] = 45,    -- Plate Shield
    [2509] = 80,    -- Steel Shield
    [2513] = 95,    -- Battle Shield
    [2525] = 100,   -- Dwarven Shield
    [2515] = 180,   -- Guardian Shield
    [2516] = 360,   -- Dragon Shield
    [2529] = 800,   -- Black Shield
    [2532] = 900,   -- Ancient Shield
    [2528] = 8000,  -- Tower Shield
    [2534] = 15000, -- Vampire Shield
    [2536] = 4000,  -- Medusa Shield
    [2537] = 300,   -- Beholder Shield
    [2520] = 8000,  -- Demon Shield
    [2539] = 6000,  -- Phoenix Shield
    [2540] = 12000, -- Mastermind Shield
    [2514] = 150,   -- Copper Shield

    -- Creature products
    [2149] = 1,     -- Small Diamond -> fallback as gold
    [5878] = 100,   -- Minotaur Leather
    [5879] = 400,   -- Minotaur Horn
    [5882] = 15,    -- Red Dragon Scale
    [5893] = 150,   -- Perfect Behemoth Fang
    [5920] = 15,    -- Green Dragon Scale
    [5925] = 15,    -- Hardened Bone
    [5948] = 50,    -- Red Dragon Leather
    [2145] = 100,   -- Small Sapphire
    [2146] = 100,   -- Small Ruby
    [2147] = 100,   -- Small Emerald
    [2149] = 100,   -- Small Diamond
    [2150] = 100,   -- Small Amethyst
    [2144] = 50,    -- Black Pearl
    [2143] = 100,   -- White Pearl
    [2154] = 300,   -- Yellow Gem
    [2155] = 500,   -- Green Gem
    [2156] = 1000,  -- Blue Gem
    [2158] = 5000,  -- Red Gem

    -- Amulets/Necklaces/Rings
    [2197] = 100,   -- Stone Skin Amulet
    [2170] = 5000,  -- Silver Amulet
    [2201] = 2000,  -- Dragon Necklace
    [2199] = 5000,  -- Garlic Necklace
    [2164] = 2000,  -- Might Ring
    [2215] = 5000,  -- Ring of Healing
    [2168] = 100,   -- Life Ring
    [2173] = 50000, -- Amulet of Loss
    [2198] = 8000,  -- Protection Amulet

    -- Food (minor loot)
    [2666] = 2,     -- Meat
    [2667] = 3,     -- Fish
    [2681] = 5,     -- Ham



    -- Misc loot
    [2229] = 50,    -- Crossbow
    [2456] = 50,    -- Bow
    [2544] = 3,     -- Arrow
    [2543] = 4,     -- Bolt
    [2546] = 20,    -- Power Bolt
}
