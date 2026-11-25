# Use Spotify playlists in Personal Radio

Select **Spotify** in the app’s **Source** menu. Save playlist links straight away, or connect your Spotify developer app to browse your library and use playback controls.

## Start a playlist from Personal Radio

1. Set up the developer app and connect your account using the steps below. Enable **Allow Spotify playback control** before selecting **Connect Spotify** and grant the requested permissions. If you already connected with read-only access, disconnect and reconnect with playback control enabled.
2. With Spotify Premium, open Spotify on the device you want to hear and play something once so it is the active Spotify device. For iPhone with CarPlay, use Spotify on that iPhone.
3. In Personal Radio, tap **Play playlist** on a saved or account playlist. Spotify plays the audio on its active device. Personal Radio shows its playback status, track details and artwork when Spotify supplies them. Use **Pause Spotify** to pause it.

The Play button starts the selected playlist from the beginning. If Spotify reports no active device, start playing something in Spotify and try again. **Open in Spotify** also works without account connection in Personal Radio. Spotify Premium downloads are for offline listening in Spotify. For audio files you own, select **My playlist** to import DRM-free files. [Spotify playback API](https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback) · [Spotify offline listening](https://support.spotify.com/uk/article/listen-offline/)

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

Personal Radio requests read-only access to private and collaborative playlists so it can show their names and links. Enabling playback control adds permission to read the active player's state and send play and pause commands. Personal Radio saves only names and canonical playlist IDs that you choose to save, plus the public Client ID for the developer app. Account results and access tokens stay in memory until you disconnect, leave the Spotify source or quit. Use **Remove** to delete a saved playlist from Personal Radio. [Spotify permissions](https://developer.spotify.com/documentation/web-api/concepts/scopes) · [Spotify authorization with PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow)

Pause playback in Personal Radio or Spotify before switching to local audio. Automated presenter, news and travel transitions around Spotify music need Spotify clearance and a successful locked-iPhone and CarPlay trial. [Spotify developer policy](https://developer.spotify.com/policy#iii-some-prohibited-applications)
