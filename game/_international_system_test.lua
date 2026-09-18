local INS = require("InternationalSystem")

local function assertEq(actual, expected, label)
    if actual ~= expected then error(label .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual)) end
end

local function assertNear(actual, expected, tolerance, label)
    if math.abs((actual or 0) - expected) > tolerance then error(label .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual)) end
end

local function makeGD()
    local gd = {
        year = 2026, month = 1, totalMonths = 0,
        group = {active = true, cash = 100000, monthlyIncome = 0, annualProfit = 0, retainedEarnings = 0},
        events = {},
    }
    function gd.AddEvent(text, kind) gd.events[#gd.events + 1] = {text = text, kind = kind} end
    function gd.FormatMoney(value) return tostring(value) end
    return gd
end

local function run()
    math.randomseed(42)
    local gd = makeGD()
    local ok = INS.RegisterDivision(gd, 20000)
    assertEq(ok, true, "register")
    assertEq(gd.group.cash, 80000, "group registration cash")

    ok = INS.TransferCapital(gd, "us", 1000)
    assertEq(ok, true, "transfer capital")
    local data = INS.EnsureFields(gd)
    assertNear(data.division.treasuryCny, 18988, 0.01, "transfer treasury")
    assertNear(data.division.foreignAccounts.us.balanceLocal * data.fxRates.us, 1000, 0.1, "transfer foreign credit")

    ok = INS.StartDueDiligence(gd, "us", "general")
    assertEq(ok, true, "start dd")
    local first = INS.MonthlyUpdate(gd, 2026, 1)
    assertEq(first.processed, true, "month one")
    local duplicate = INS.MonthlyUpdate(gd, 2026, 1)
    assertEq(duplicate.skipped, true, "month idempotent")
    local second = INS.MonthlyUpdate(gd, 2026, 2)
    assertEq(second.processed, true, "month two")
    assertEq(data.dueDiligence.us.status, "completed", "dd complete")

    ok = INS.InvestDirectLand(gd, "us", 1000, "sale")
    assertEq(ok, true, "direct sale")
    INS.UpgradeCapacity(gd)
    ok = INS.InvestDirectLand(gd, "us", 1000, "rent")
    assertEq(ok, true, "direct rent")
    INS.UpgradeCapacity(gd)
    ok = INS.BuyExistingAsset(gd, "us", 500, "写字楼")
    assertEq(ok, true, "existing asset")
    ok = INS.InvestFund(gd, "us", 300, "REITs")
    assertEq(ok, true, "fund")
    INS.UpgradeCapacity(gd)
    INS.HireTeam(gd, "manager", 1)
    ok = INS.CreateJointVenture(gd, "us", 800, "本地伙伴", 50)
    assertEq(ok, true, "joint venture")

    data = INS.EnsureFields(gd)
    assertEq(data.capacityUsed, 7, "capacity derived")

    ok = INS.ApplyDivisionBankLoan(gd, "us", 1000, 12, "credit")
    assertEq(ok, true, "bank loan")
    local loan = data.division.bankLoans[1]
    loan.remainMonths = 1
    data.division.treasuryCny = 0
    data.division.foreignAccounts.us.balanceLocal = 0
    local loanMonth = INS.MonthlyUpdate(gd, 2026, 3)
    assertEq(loanMonth.processed, true, "loan month")
    assertEq(#data.division.bankLoans, 1, "unpaid loan retained")
    assertEq(data.division.bankLoans[1].status, "overdue", "loan overdue")
    assertEq(data.division.totalDebtCny > 0, true, "debt retained")

    local lifecycle = makeGD()
    assert(INS.RegisterDivision(lifecycle, 20000))
    local lifeData = INS.EnsureFields(lifecycle)
    lifeData.dueDiligence.us = {countryId = "us", status = "completed", remainMonths = 0}
    INS.UpgradeCapacity(lifecycle)
    assert(INS.InvestDirectLand(lifecycle, "us", 1000, "sale"))
    assert(INS.InvestDirectLand(lifecycle, "us", 1000, "rent"))
    for _, project in ipairs(lifeData.projects) do project.totalMonths = 1; project.remainMonths = 1 end
    local lifeMonth = INS.MonthlyUpdate(lifecycle, 2026, 1)
    assertEq(lifeMonth.processed, true, "lifecycle month")
    assertEq(#lifeData.projects, 0, "completed projects removed")
    assertEq(#lifeData.assets, 1, "rent project converted asset")
    assertEq(#lifeData.history >= 2, true, "project history retained")
    assertEq(lifeMonth.income >= 0, true, "sale project income returned")

    local rollback = makeGD()
    assert(INS.RegisterDivision(rollback, 5000))
    local rollbackData = INS.EnsureFields(rollback)
    rollbackData.dueDiligence.us = {countryId = "us", status = "processing", remainMonths = 1}
    rollback.AddEvent = function() error("forced monthly failure") end
    local failed = INS.MonthlyUpdate(rollback, 2026, 1)
    assertEq(failed.failed, true, "monthly failure reported")
    rollbackData = rollback.international
    assertEq(rollbackData.lastMonthlySerial, nil, "failed month not committed")
    assertEq(rollbackData.dueDiligence.us.remainMonths, 1, "failed month rolled back")
    rollback.AddEvent = function() end
    local retried = INS.MonthlyUpdate(rollback, 2026, 1)
    assertEq(retried.processed, true, "failed month retry")

    local legacy = makeGD()
    legacy.international = {
        division = {active = 1, bankLoans = {{id = "same", countryId = "us", remainingCny = 200, amountCny = 200, rate = 0.07, remainMonths = 12}}},
        loans = {{id = "same", countryId = "us", remainingCny = 200, amountCny = 200, rate = 0.07, remainMonths = 12}},
        projects = {}, assets = {}, funds = {},
    }
    local migrated = INS.EnsureFields(legacy)
    assertEq(migrated.division.active, true, "legacy boolean")
    assertEq(#migrated.division.bankLoans, 1, "legacy loan dedupe")
    assertEq(#migrated.loans, 0, "legacy loans cleared")
    assertEq(migrated.totalProfitCny, 0, "legacy total profit")

    gd.group.cash = 0
    data.division.treasuryCny = 1000
    data.division.retainedEarningsCny = 500
    ok = INS.DistributeDivisionDividend(gd, 500)
    assertEq(ok, true, "division dividend")
    assertEq(gd.group.cash, 500, "group dividend cash")
    assertEq(gd.group.monthlyIncome, 500, "group dividend income")
    assertEq(gd.group.annualProfit, 500, "group dividend annual")
    assertEq(gd.group.retainedEarnings, 500, "group dividend retained")

    print("[INTERNATIONAL-TEST] PASS assertions=42")
end

function Start()
    local ok, err = pcall(run)
    if not ok then
        print("[INTERNATIONAL-TEST] FAIL " .. tostring(err))
        log:Write(LOG_ERROR, tostring(err))
    end
    engine:Exit()
end
