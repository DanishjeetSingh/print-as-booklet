const NATIVE_HOST = "com.danishjeetsingh.print_booklet";

async function setStatus(tabId, text, color, title) {
  await chrome.action.setBadgeBackgroundColor({ tabId, color });
  await chrome.action.setBadgeText({ tabId, text });
  await chrome.action.setTitle({ tabId, title });
}

chrome.action.onClicked.addListener(async (tab) => {
  const tabId = tab.id;

  try {
    if (!tabId || !tab.url || !/^https?:\/\//i.test(tab.url)) {
      throw new Error("Open a PDF from an http:// or https:// address first.");
    }

    const tabOrigin = new URL(tab.url).origin;
    const originPattern = `${tabOrigin}/*`;
    const requestedOrigins = [originPattern];
    if (new URL(tab.url).hostname === "substack.com" || new URL(tab.url).hostname.endsWith(".substack.com")) {
      requestedOrigins.push("https://substack.com/*", "https://*.substack.com/*");
    }
    const siteAccessGranted = await chrome.permissions.request({
      origins: requestedOrigins
    });
    if (!siteAccessGranted) {
      throw new Error("Site access is required to retrieve the authenticated PDF.");
    }

    await setStatus(tabId, "…", "#5f6368", "Preparing booklet");

    const cookies = await chrome.cookies.getAll({ url: tab.url });
    const response = await chrome.runtime.sendNativeMessage(NATIVE_HOST, {
      url: tab.url,
      cookies: cookies.map((cookie) => ({
        domain: cookie.domain,
        expirationDate: cookie.expirationDate,
        httpOnly: cookie.httpOnly,
        name: cookie.name,
        path: cookie.path,
        secure: cookie.secure,
        value: cookie.value
      }))
    });

    if (!response?.ok) {
      throw new Error(response?.error || "The local booklet helper failed.");
    }

    await setStatus(
      tabId,
      String(response.pageCount),
      "#188038",
      `Submitted ${response.pageCount} PDF pages as a booklet`
    );
    setTimeout(() => {
      chrome.action.setBadgeText({ tabId, text: "" }).catch(() => {});
      chrome.action.setTitle({ tabId, title: "Print current PDF as booklet" }).catch(() => {});
    }, 5000);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (tabId) {
      await setStatus(tabId, "!", "#d93025", message);
    }
    console.warn(message);
  }
});
