var g_Terms = {
	"Service": {
		"title": translate("Terms of Service"),
		"instruction": translate("Please read the Terms of Service"),
		"file": "prelobby/common/terms/Terms_of_Service",
		"read": false
	},
	"Use": {
		"title": translate("Terms of Use"),
		"instruction": translate("Please read the Terms of Use"),
		"file": "prelobby/common/terms/Terms_of_Use",
		"read": false
	}
};

function openTerms(terms)
{
	g_Terms[terms].read = true;
	Engine.GetGUIObjectByName("agreeTerms").enabled = g_Terms.Service.read && g_Terms.Use.read;

	Engine.PushGuiPage("page_manual.xml", {
		"page": g_Terms[terms].file,
		"title": g_Terms[terms].title,
		"callback": "updateFeedback"
	});
}

function checkTerms()
{
	for (let page in g_Terms)
		if (!g_Terms[page].read)
			return g_Terms[page].instruction;

	if (!Engine.GetGUIObjectByName("agreeTerms").checked)
		return translate("Please agree to the Terms of Service and Terms of Use");

	return "";
}
