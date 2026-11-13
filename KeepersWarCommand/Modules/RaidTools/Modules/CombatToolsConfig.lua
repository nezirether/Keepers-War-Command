local KRT = KeepersRaidTools

KRT:RegisterTab("Combat Tools", function(parent)
    return KRT.Components.GetSubTabGroup(parent, {
        { name = "Cooldowns", setup = KRT.CooldownRoster.SetupConfig },
        { name = "Timer", setup = KRT.CombatTimer.SetupConfig },
    })
end)
