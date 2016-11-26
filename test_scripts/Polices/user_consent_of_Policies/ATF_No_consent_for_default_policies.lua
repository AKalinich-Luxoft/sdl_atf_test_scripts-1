------------- --------------------------------------------------------------------------------
-- Requirement summary:
-- 		[Policies]: never ask a user for a consent for "default" policies applied
--
-- Description:
-- 		Condition for never asking for consent for "default" permissions by PoliciesManager.
--		After PTU the 'groups' in 'default' section were updated AND registered app is assigned with 'default' policies
--
-- Preconditions:
--		Delete log files and policy table from previous ignition cycle
--		Activate app -> consent device
--		Add new session
--		Register second app(device is consented)-> app is assigned with default permissions
--		Perform PTU with new permission groups in default
--		Activate second session
--
-- Expected result:
-- 		PoliciesManager must not ask the User for consent for "default" permissions
---------------------------------------------------------------------------------------------
--[[ General configuration parameters ]]
config.deviceMAC = "12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0"

--[[ Required Shared libraries ]]
local commonFunctions = require("user_modules/shared_testcases/commonFunctions")
local commonSteps = require("user_modules/shared_testcases/commonSteps")

--[[ General Precondition before ATF start ]]
commonSteps:DeleteLogsFileAndPolicyTable()

--[[ General Settings for configuration ]]
Test = require("connecttest")
require("user_modules/AppTypes")
local mobile_session = require('mobile_session')

--[[ Precondition ]]
function Test:Precondition_ActivateRegisteredApp()
  local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.applications["Test Application"]})
  EXPECT_HMIRESPONSE(RequestId, {result = { code = 0, isAppPermissionsRevoked = false, isAppRevoked = false, isSDLAllowed = false, isPermissionsConsentNeeded = true, method ="SDL.ActivateApp", priority ="NONE"}})
  :Do(function(_,data)
  if data.result.isSDLAllowed ~= false then
    commonFunctions:userPrint(31, "Error: wrong behavior of SDL - device needs to be consented on HMI")
  else
    local RequestIdGetMessage = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", {language = "EN-US", messageCodes = {"DataConsent"}})
    EXPECT_HMIRESPONSE(RequestIdGetMessage)
    :Do(function()
    self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality",
    {allowed = true, source = "GUI", device = {id = config.deviceMAC, name = "127.0.0.1"}})
    EXPECT_HMICALL("BasicCommunication.ActivateApp")
    :Do(function()
    self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})
    end)
    :Times(2)
    end)
  end
  end)
  EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "FULL", systemContext = "MAIN", audioStreamingState = "AUDIBLE"})
end

function Test:Precondition_AddSession2()
  self.mobileSession1 = mobile_session.MobileSession(self,self.mobileConnection)
  self.mobileSession1:StartService(7)
end

function Test:Precondition_RegisterApp2()
  local RequestIdSecondRegister = self.mobileSession1:SendRPC("RegisterAppInterface", config.application2.registerAppInterfaceParams)
  EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered")
  :Do(function(_,data)
  self.HMIAppID2 = data.params.application.appID
  end)
  self.mobileSession1:ExpectResponse(RequestIdSecondRegister, { success = true, resultCode = "SUCCESS" })
  self.mobileSession1:ExpectNotification("OnHMIStatus", {hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"})
end

function Test:Precondition_PTU_with_new_default_permissions()
  local CorIdSystemRequest = self.mobileSession:SendRPC("SystemRequest",
  {
    fileName = "PolicyTableUpdate",
    requestType = "PROPRIETARY",
    appID = self.HMIAppID2
  },
  "files/PTU_NewDefaultPermissions.json")
  local systemRequestId
  EXPECT_HMICALL("BasicCommunication.SystemRequest")
  :Do(function(_,data)
  systemRequestId = data.id
  self.hmiConnection:SendNotification("SDL.OnReceivedPolicyUpdate",
  {
    policyfile = "/tmp/fs/mp/images/ivsu_cache/PolicyTableUpdate"
  }
  )
  local function to_run()
    self.hmiConnection:SendResponse(systemRequestId,"BasicCommunication.SystemRequest", "SUCCESS", {})
  end

  RUN_AFTER(to_run, 500)
  end)
  EXPECT_RESPONSE(CorIdSystemRequest, { success = true, resultCode = "SUCCESS"})
  :Do(function()
  local RequestIdGetUserFriendlyMessage = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", {language = "EN-US", messageCodes = {"StatusUpToDate"}})
  EXPECT_HMIRESPONSE(RequestIdGetUserFriendlyMessage)
  end)
end


--[[ Test ]]
commonFunctions:newTestCasesGroup("Test")

function Test:Check_no_consent_for_default_permissions()
  local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.HMIAppID2 })
  EXPECT_HMIRESPONSE(RequestId, {result = { code = 0, isAppPermissionsRevoked = false, isAppRevoked = false, isPermissionsConsentNeeded = false, isSDLAllowed = true, method ="SDL.ActivateApp", priority ="NONE"}})
  :Do(function(_,data)
  --Device is consented already, so no consent is needed:
  if data.result.isSDLAllowed ~= true and data.result.isPermissionsConsentNeeded ~= false  then
    commonFunctions:userPrint(31, "Error: wrong behavior of SDL - device already consented")
  else
    self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})
  end
  end)
  EXPECT_NOTIFICATION("OnHMIStatus", {})
end

--[[ Postconditions ]]
commonFunctions:newTestCasesGroup("Postconditions")

function Test.Postcondition_SDLForceStop()
  commonFunctions:SDLForceStop()
end