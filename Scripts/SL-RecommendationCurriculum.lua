-- Editable recommendation curriculum for SL-Recommendations v20+.
--
-- POLICY lives here.  The scorer reads this table dynamically.

SLRecommendationCurriculum = {
    Version = 5,

    JokeMeterMax = 30,

    Skill = {
        decentDP = 0.80,
        strongDP = 0.90,
        reliableMinCharts = 2,
        masteryMinCharts = 4,
        strongMasteryMinCharts = 3,
    },

    RecentInterest = {
        minLevel = 9,
        lookbackDays = 120,
        minCharts = 2,
        minNormalizedInterest = 0.35,
        maxSections = 2,

        meterPreferenceSigma = 1.25,

        -- Reserve only a minority of "More X" for progression; the rest
        -- follows the levels where the player actually plays X.
        ceilingQuota = 0.25,
        ceilingBand = 1,
    },

    -- Explicit notation in Description/ChartStyle is considered authoritative.
    -- '-' means light presence; no suffix means clear presence; '+'/'++' mean
    -- increasingly heavy emphasis.
    NotationStrength = {
        minus = 0.45,
        plain = 0.72,
        plus = 0.90,
        doublePlus = 1.00,
    },

    -- Separate from presence confidence.  Plain notation means definite
    -- presence, while +/++ communicate increasing emphasis.
    NotationIntensity = {
        minus = 0.25,
        plain = 0.50,
        plus = 0.80,
        doublePlus = 1.00,
    },

    Tech = {
        crossovers = {
            label = "Crossover Recs",
            interestLabel = "More Crossovers",
            notation = {"XO", "CROSSOVER", "CROSSOVERS", "CROSSUNDER", "CROSSUNDERS"},
            minEngineCount = 6,
            heavyEngineCount = 30,
            heavyEngineRate = 8.00,
            minCandidateIntensity = 0.25,
            fullFitRate = 0.75,
            minCandidateFit = 0.42,
            interestMinEvidence = 0.35,
            trainingMinDP = 0.75,
            masteryDP = 0.85,
            masteryMinCharts = 4,
            strongDP = 0.90,
            automaticMaxResults = 25,
            interestMaxResults = 18,
            interestMaxLevel = 9,
        },

        footswitches = {
            label = "Footswitch Recs",
            interestLabel = "More Footswitches",
            notation = {"FS", "HS", "UPSH", "FOOTSWITCH", "FOOTSWITCHES", "HOLDSWITCH", "HOLDSWITCHES"},
            minEngineCount = 4,
            heavyEngineCount = 20,
            heavyEngineRate = 5.00,
            minCandidateIntensity = 0.25,
            fullFitRate = 0.55,
            minCandidateFit = 0.42,
            interestMinEvidence = 0.35,
            trainingMinDP = 0.75,
            masteryDP = 0.85,
            masteryMinCharts = 4,
            strongDP = 0.90,
            automaticMaxResults = 25,
            interestMaxResults = 18,
            interestMaxLevel = 11,
        },

        brackets = {
            label = "Bracket Recs",
            interestLabel = "More Brackets",
            notation = {"BR", "BT", "BRACKET", "BRACKETS", "BRACKETTAP", "BRACKETTAPS"},
            minEngineCount = 4,
            heavyEngineCount = 24,
            heavyEngineRate = 8.00,
            minCandidateIntensity = 0.28,
            fullFitRate = 0.50,
            minCandidateFit = 0.42,
            interestMinEvidence = 0.35,
            trainingMinDP = 0.75,
            masteryDP = 0.85,
            masteryMinCharts = 4,
            strongDP = 0.90,
            automaticMaxResults = 25,
            interestMaxResults = 18,
        },

        sideswitches = {
            label = "Sideswitch Recs",
            interestLabel = "More Sideswitches",
            notation = {"SS", "SIDESWITCH", "SIDESWITCHES"},
            minEngineCount = 3,
            heavyEngineCount = 15,
            heavyEngineRate = 4.00,
            minCandidateIntensity = 0.25,
            fullFitRate = 0.40,
            minCandidateFit = 0.40,
            interestMinEvidence = 0.35,
            trainingMinDP = 0.75,
            masteryDP = 0.85,
            masteryMinCharts = 4,
            strongDP = 0.90,
            automaticMaxResults = 22,
            interestMaxResults = 16,
            interestMinLevel = 11,
            interestRequiresMastery = {"crossovers", "footswitches"},
        },

        jacks = {
            label = "Jack Recs",
            interestLabel = "More Jacks",
            notation = {"JA", "JH", "JACK", "JACKS", "JACKHAMMER", "JACKHAMMERS"},
            minEngineCount = 8,
            heavyEngineCount = 40,
            heavyEngineRate = 14.00,
            minCandidateIntensity = 0.25,
            fullFitRate = 1.00,
            minCandidateFit = 0.45,
            interestMinEvidence = 0.38,
            trainingMinDP = 0.75,
            masteryDP = 0.85,
            masteryMinCharts = 4,
            strongDP = 0.90,
            automaticMaxResults = 22,
            interestMaxResults = 16,
        },

        doublesteps = {
            label = "Doublestep Recs",
            interestLabel = "More Doublesteps",
            notation = {"DS", "DOUBLESTEP", "DOUBLESTEPS"},
            minEngineCount = 5,
            heavyEngineCount = 25,
            heavyEngineRate = 6.00,
            minCandidateIntensity = 0.25,
            fullFitRate = 0.70,
            minCandidateFit = 0.44,
            interestMinEvidence = 0.38,
            trainingMinDP = 0.75,
            masteryDP = 0.85,
            masteryMinCharts = 4,
            strongDP = 0.90,
            automaticMaxResults = 20,
            interestMaxResults = 15,
            interestMinLevel = 11,
        },
    },

    -- Parsed and retained as trusted chart-description tags even where the
    -- current recommendation model does not yet have a dedicated section.
    AdditionalNotation = {
        bursts = {"BU", "BURST", "BURSTS"},
        doubletaps = {"DT", "DOUBLETAP", "DOUBLETAPS"},
        xmod = {"XMOD"},
        flams = {"FL", "FLAM", "FLAMS"},
        rhythms = {"RH", "SKT", "RHYTHM", "RHYTHMS", "SKITTLE", "SKITTLES"},
        stream = {"STR", "STREAM", "STREAMS"},
        stepjumps = {"SJ", "STEPJUMP", "STEPJUMPS"},
        roundsteps = {"RS", "ROUNDSTEP", "ROUNDSTEPS"},
        laterals = {"AN", "SC", "AFRONOVA", "AFRONOVAS", "SCOOBY", "SCOOBIES"},
        mods = {"MODS"},
    },

    -- Automatic Quirky Recs are a level-10 teaching/exposure section.  At 11+
    -- it only comes back when the player's recent history shows actual interest.
    Quirkiness = {
        automaticLevel = 10,
        section = "Quirky Recs",
        interestSection = "More Quirky Charts",
        candidateMin = 0.42,
        maxResults = 20,
        interestMaxResults = 16,
        interestMinLevel = 10,
        interestLookbackDays = 120,
        interestMinCharts = 2,
        interestMin = 0.32,

        editDifficultyPoints = 0.10,
    },

    Rhythms = {
        section = "More Rhythms",

        notation = {
            "RH",
            "SKT",
            "RHYTHM",
            "RHYTHMS",
            "SKITTLE",
            "SKITTLES",
        },

        streamNotation = {
            "STR",
            "STREAM",
            "STREAMS",
        },

        chaosThreshold = 1.20,
        chaosFull = 2.25,

        beginnerChaosThreshold = 1.00,
        beginnerChaosFull = 2.00,

        candidateMin = 0.42,

        interestLookbackDays = 120,
        interestMinCharts = 2,
        interestMin = 0.34,
        interestMinLevel = 9,

        earlyInterestFamiliarity = 0.65,

        maxResults = 16,

        familiarityPassedCharts = 3,
        familiarityRecentCharts = 4,

        goodScoreDP = 0.80,
        frequentPlayCount = 3,

        beginnerPenaltyStrength = 0.88,
    },

    Levels = {
        [8] = {
            automatic = {
                {tech = "crossovers"},
            },
        },
        [9] = {
            automatic = {
                {tech = "crossovers"},
            },
        },
        [10] = {
            automatic = {
                {tech = "footswitches"},
            },
        },
        [11] = {
            automatic = {
                {tech = "footswitches"},
                {tech = "brackets"},
                {
                    tech = "sideswitches",
                    requiresMastery = {"crossovers", "footswitches"},
                },
            },
        },
        [12] = {
            automatic = {
                {tech = "brackets", hideWhenMastered = true},
            },
        },
    },

    Bands = {
        {
            minLevel = 1,
            maxLevel = 10,

            techLevelSigma = 1.00,
            interestTechLevelSigma = 1.25,

            -- Introductory targeted-tech recommendations should be strong
            -- examples of the requested pattern at an appropriate level.
            weights = {
                techIntensity = 0.43,
                techLevelFit = 0.20,
                popularity = 0.10,
                machineRecentActivity = 0.06,
                communityFavorite = 0.06,
                communityScoreability = 0.06,
                beginnerSafety = 0.05,
                exploration = 0.02,
                metadata = 0.02,
            },

            interestWeights = {
                techIntensity = 0.45,
                techLevelFit = 0.18,
                techHistoryLevelFit = 0.08,
                popularity = 0.05,
                machineRecentActivity = 0.04,
                communityFavorite = 0.04,
                communityScoreability = 0.05,
                beginnerSafety = 0.05,
                exploration = 0.03,
                metadata = 0.03,
            },
        },

        {
            minLevel = 11,
            maxLevel = 12,

            techLevelSigma = 1.25,
            interestTechLevelSigma = 1.50,

            weights = {
                techIntensity = 0.45,
                techLevelFit = 0.20,
                popularity = 0.06,
                communityFavorite = 0.05,
                communityScoreability = 0.05,
                metadata = 0.05,
                tech = 0.04,
                stamina = 0.04,
                localPeerPerformance = 0.03,
                exploration = 0.03,
            },

            interestWeights = {
                techIntensity = 0.48,
                techLevelFit = 0.14,
                techHistoryLevelFit = 0.10,
                metadata = 0.05,
                tech = 0.03,
                stamina = 0.05,
                localPeerPerformance = 0.04,
                localScoringEase = 0.03,
                popularity = 0.03,
                communityFavorite = 0.02,
                exploration = 0.03,
            },
        },

        {
            minLevel = 13,
            maxLevel = 999,

            techLevelSigma = 1.75,
            interestTechLevelSigma = 2.00,

            -- For experienced players, a dedicated tech section is primarily
            -- about the requested technique and the player's current working
            -- level.  Taste/stepartist is a tie-breaker, not a substitute.
            weights = {
                techIntensity = 0.52,
                techLevelFit = 0.18,
                stamina = 0.07,
                localPeerPerformance = 0.05,
                localScoringEase = 0.03,
                metadata = 0.04,
                personalAffinity = 0.02,
                exploration = 0.04,
                popularity = 0.03,
                tech = 0.02,
            },

            interestWeights = {
                techIntensity = 0.55,
                techHistoryLevelFit = 0.12,
                techLevelFit = 0.06,
                stamina = 0.07,
                localPeerPerformance = 0.05,
                localScoringEase = 0.04,
                metadata = 0.06,
                personalAffinity = 0.03,
                exploration = 0.02,
            },
        },
    },
}
