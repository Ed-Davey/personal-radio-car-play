# Use Spotify playlists in Personal Radio

Select **Spotify** in the app’s **Source** menu. You can save playlist links straight away or connect a Spotify developer app to browse your library. Select **Open in Spotify** and press **Play** in Spotify while parked. Spotify handles music playback and CarPlay controls.

## Save a Spotify playlist link

1. In Spotify, open the playlist and choose **Share → Copy link to playlist**.
2. In Personal Radio, paste the link into **Spotify playlist link or URI**, optionally name it and select **Save playlist**.
3. Select **Open in Spotify** for the saved entry. If Spotify is available as a universal link, it opens the playlist in the app. A browser can open the same link. [Spotify content linking](https://developer.spotify.com/documentation/ios/tutorials/content-linking) · [Spotify on CarPlay](https://connect.spotify.com/devices/apple-car-play)

## Browse your Spotify library

1. In the Spotify developer dashboard, register the exact redirect URI below and select the Web API. Add your Spotify account to the developer app's user list if Spotify requires it. Spotify Development Mode requires the app owner to have Premium and limits the number of users. [Spotify app setup](https://developer.spotify.com/documentation/web-api/concepts/apps) · [Spotify quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)

   ```text
   com.ed-davey.personalradio.spotify://auth/callback
   ```

2. In Personal Radio, open **Connect your Spotify library**. Paste only the public developer **Client ID**, then select **Connect Spotify**. Sign in through Spotify’s consent screen.
3. Open any returned playlist in Spotify or save it to your on-device list. Use **Load more playlists** for another page. Select **Disconnect** to clear the account session. [Spotify playlist endpoint](https://developer.spotify.com/documentation/web-api/reference/get-a-list-of-current-users-playlists)

## Spotify data on this device

Personal Radio uses Spotify’s read-only playlist permission to show your playlist names and links. It saves only names and canonical playlist IDs that you choose to save, plus the public Client ID for the developer app. Account results and access tokens stay in memory until you disconnect, leave the Spotify source or quit. Use **Remove** to delete a saved playlist from Personal Radio. [Spotify authorization with PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow)

The Spotify playlist path is a user-triggered handoff. Automated presenter, news and travel transitions around Spotify music need Spotify clearance and a successful locked-iPhone and CarPlay trial. [Spotify developer policy](https://developer.spotify.com/policy#iii-some-prohibited-applications) · [Spotify iOS lifecycle](https://developer.spotify.com/documentation/ios/concepts/application-lifecycle)
