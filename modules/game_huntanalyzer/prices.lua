-- Item price table for balance tracker
-- Prices indexed by CLIENT IDs (mapped from items.otb)
-- Server sends client IDs via ItemType:getClientId()

SUPPLY_PRICES = {
    -- Fluids
    [2874] = 80,   -- Vial

    -- Runes
    [3152] = 95,   -- Intense Healing Rune
    [3160] = 175,  -- Ultimate Healing Rune
    [3155] = 325,  -- Sudden Death Rune
    [3198] = 125,  -- Heavy Magic Missile
    [3191] = 180,  -- Great Fireball Rune
    [3174] = 40,   -- Light Magic Missile
    [3200] = 250,  -- Explosion Rune
    [3166] = 340,  -- Energy Wall Rune
    [3178] = 210,  -- Chameleon Rune
    [3192] = 235,  -- Firebomb Rune
    [3177] = 80,   -- Convince Creature Rune
    [3153] = 65,   -- Antidote Rune
    [3148] = 45,   -- Destroy Field Rune
    [3172] = 65,   -- Poison Field Rune
    [3164] = 115,  -- Energy Field Rune
    [3176] = 210,  -- Poison Wall Rune
    [3147] = 10,   -- Blank Rune

    -- Premium runes
    [3179] = 130,  -- Envenom Rune
    [3197] = 80,   -- Desintegrate Rune
    [3173] = 170,  -- Poison Bomb Rune
    [3195] = 210,  -- Soulfire Rune
    [3149] = 325,  -- Energy Bomb Rune
    [3180] = 350,  -- Magic Wall Rune
    [3203] = 375,  -- Animate Dead Rune
    [3165] = 700,  -- Paralyze Rune
}

LOOT_PRICES = {
    -- Currency
    [3031] = 1,       -- Gold Coin
    [3035] = 100,     -- Platinum Coin
    [3043] = 10000,   -- Crystal Coin

    -- Weapons
    [3267] = 2,       -- Dagger
    [3268] = 4,       -- Hand Axe
    [3277] = 3,       -- Spear
    [3272] = 5,       -- Rapier
    [3274] = 7,       -- Axe
    [3273] = 12,      -- Sabre
    [3264] = 25,      -- Sword
    [3286] = 30,      -- Mace
    [3305] = 120,     -- Battle Hammer
    [3266] = 80,      -- Battle Axe
    [3282] = 90,      -- Morning Star
    [3265] = 450,     -- Two Handed Sword
    [3269] = 400,     -- Halberd
    [3297] = 900,     -- Serpent Sword
    [3281] = 17000,   -- Giant Sword
    [3322] = 2000,    -- Dragon Hammer
    [3318] = 2000,    -- Knight Axe
    [3324] = 6000,    -- Skull Staff
    [3307] = 150,     -- Scimitar
    [3299] = 50,      -- Poison Dagger
    [3320] = 10000,   -- Fire Axe
    [3295] = 8000,    -- Bright Sword
    [3288] = 10000,   -- Magic Longsword
    [3278] = 500,     -- Magic Plate Armor (Spear)
    [3311] = 6000,    -- Clerical Mace
    [3319] = 4000,    -- Stonecutter Axe

    -- Armor
    [3361] = 12,      -- Leather Armor
    [3358] = 70,      -- Chain Armor
    [3359] = 150,     -- Brass Armor
    [3357] = 400,     -- Plate Armor
    [3370] = 5000,    -- Knight Armor
    [3360] = 20000,   -- Golden Armor
    [3383] = 400,     -- Dark Armor
    [3366] = 6400,    -- Magic Plate Armor
    [3381] = 900,     -- Crown Armor
    [3386] = 1200,    -- Dragon Scale Mail
    [3388] = 150,     -- Demon Armor
    [3369] = 5000,    -- Warrior Helmet

    -- Helmets
    [3355] = 4,       -- Leather Helmet
    [3352] = 17,      -- Chain Helmet
    [3354] = 30,      -- Brass Helmet
    [3367] = 66,      -- Viking Helmet
    [3353] = 145,     -- Iron Helmet
    [3351] = 190,     -- Steel Helmet
    [3384] = 250,     -- Dark Helmet
    [3356] = 450,     -- Devil Helmet
    [3373] = 500,     -- Strange Helmet
    [3574] = 150,     -- Mystic Turban
    [3365] = 12000,   -- Golden Helmet
    [3385] = 2500,    -- Crown Helmet
    [3392] = 3000,    -- Royal Helmet

    -- Legs
    [3558] = 25,      -- Chain Legs
    [3371] = 5000,    -- Knight Legs
    [3382] = 1200,    -- Crown Legs
    [3364] = 30000,   -- Golden Legs
    [3557] = 1000,    -- Plate Legs

    -- Boots
    [3552] = 2,       -- Leather Boots
    [3079] = 3000,    -- Boots of Haste
    [3554] = 10000,   -- Steel Boots

    -- Shields
    [3412] = 5,       -- Wooden Shield
    [3411] = 16,      -- Brass Shield
    [3410] = 45,      -- Plate Shield
    [3409] = 80,      -- Steel Shield
    [3413] = 95,      -- Battle Shield
    [3425] = 100,     -- Dwarven Shield
    [3415] = 180,     -- Guardian Shield
    [3416] = 360,     -- Dragon Shield
    [3429] = 800,     -- Black Shield
    [3432] = 900,     -- Ancient Shield
    [3428] = 8000,    -- Tower Shield
    [3434] = 15000,   -- Vampire Shield
    [3436] = 4000,    -- Medusa Shield
    [3437] = 300,     -- Beholder Shield
    [3420] = 8000,    -- Demon Shield
    [3439] = 6000,    -- Phoenix Shield
    [3440] = 12000,   -- Mastermind Shield
    [3414] = 150,     -- Copper Shield

    -- Creature products
    [3028] = 100,     -- Small Sapphire
    [3029] = 100,     -- Small Ruby
    [3030] = 100,     -- Small Emerald
    [3032] = 100,     -- Small Diamond
    [3033] = 100,     -- Small Amethyst
    [3027] = 50,      -- Black Pearl
    [3026] = 100,     -- White Pearl
    [3037] = 300,     -- Yellow Gem
    [3038] = 500,     -- Green Gem
    [3039] = 1000,    -- Blue Gem
    [3041] = 5000,    -- Red Gem

    -- Amulets/Necklaces/Rings
    [3081] = 100,     -- Stone Skin Amulet
    [3054] = 5000,    -- Silver Amulet
    [3085] = 2000,    -- Dragon Necklace
    [3083] = 5000,    -- Garlic Necklace
    [3048] = 2000,    -- Might Ring
    [3099] = 5000,    -- Ring of Healing
    [3052] = 100,     -- Life Ring
    [3057] = 50000,   -- Amulet of Loss
    [3082] = 8000,    -- Protection Amulet

    -- Food
    [3577] = 2,       -- Meat
    [3578] = 3,       -- Fish
    [3592] = 5,       -- Ham

    -- Misc loot
    [3114] = 50,      -- Crossbow
    [3350] = 50,      -- Bow
    [3447] = 3,       -- Arrow
    [3446] = 4,       -- Bolt
    [3449] = 20,      -- Power Bolt
}
