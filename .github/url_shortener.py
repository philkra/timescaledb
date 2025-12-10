#!/usr/bin/env python3
"""
BL.INK URL Shortener Script

This script extracts URLs from text and creates shortened links using the BL.INK API.
It requires BL.INK API credentials to be set as environment variables.

Environment Variables:
    BLINK_EMAIL: Your BL.INK account email
    BLINK_PASSWORD: Your BL.INK account password
    BLINK_DOMAIN_NAME: The domain name to use for creating short links
    BLINK_API_BASE: (Optional) API base URL, defaults to https://app.bl.ink/api/v4
"""

import os
import sys
import re
import requests
from typing import List, Optional, Dict

# Add a slash at the end to avoid partial matches
EXCLUDE_DOMAINS = ["github.com/", "tsdb.co/"]


class BlinkAPIError(Exception):
    """Custom exception for BL.INK API errors"""
    pass


class BlinkShortener:
    def __init__(
        self,
        email: str,
        password: str,
        api_base: str = "https://app.bl.ink/api/v4"
    ):
        """
        Initialize the BL.INK URL shortener.
        
        Args:
            email: BL.INK account email
            password: BL.INK account password
            api_base: Base URL for the BL.INK API
        """
        self.email = email
        self.password = password
        self.api_base = api_base.rstrip('/')
        self.access_token = None
    
    def get_access_token(self) -> str:
        """
        Get a valid access token from the BL.INK API.
        
        Returns:
            Access token string
            
        Raises:
            BlinkAPIError: If authentication fails
        """
        url = f"{self.api_base}/access_token"
        
        # Prepare auth payload
        payload = {
            "email": self.email,
            "password": self.password
        }
        
        try:
            response = requests.post(url, json=payload)
            response.raise_for_status()
            
            data = response.json()
            if data.get("success") == 1:
                self.access_token = data.get("access_token")
                return self.access_token
            else:
                raise BlinkAPIError("Authentication failed: Invalid response")
                
        except requests.exceptions.RequestException as e:
            raise BlinkAPIError(f"Failed to get access token: {str(e)}")
        
    def get_domain_id(self, domain_name: str) -> int:
        """
        Get the domain ID from the BL.INK API.
        
        Args:
            domain_name: The domain name to get the ID
            
        Returns:
            int
            
        Raises:
            BlinkAPIError: If fetch fails
        """
        if not self.access_token:
            self.get_access_token()
        
        endpoint = f"{self.api_base}/domains?domain_name={domain_name}"
        headers = {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json"
        }
        try:
            response = requests.get(endpoint, headers=headers)
            response.raise_for_status()
            
            data = response.json()
            return data['objects'][0]['id']
        except requests.exceptions.RequestException as e:
            raise BlinkAPIError(f"Failed to get the domain ID: {str(e)}")
        
    def link_exists(self, url: str, domain_id: int) -> Dict:
        """
        Check if the URL has a short link
        
        Args:
            url: Lookup for existence
            
        Returns:
            Dict
            
        Raises:
            BlinkAPIError: If request fails
        """
        if not self.access_token:
            self.get_access_token()
        
        endpoint = f"{self.api_base}/{domain_id}/links?url={url}"
        headers = {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json"
        }
        try:
            response = requests.get(endpoint, headers=headers)
            response.raise_for_status()
            
            data = response.json()
            return None if data.get("count") == 0 else data.get('objects')[0]
        except requests.exceptions.RequestException as e:
            raise BlinkAPIError(f"Failed to get the domain ID: {str(e)}")
    
    def create_short_link(self, url: str, domain_id: int) -> Dict:
        """
        Create a shortened link using the BL.INK API.
        
        Args:
            url: The long URL to shorten
            domain_id: The domain ID to use
            
        Returns:
            Dictionary containing the short link information
            
        Raises:
            BlinkAPIError: If link creation fails
        """
        if not self.access_token:
            self.get_access_token()
        
        endpoint = f"{self.api_base}/{domain_id}/links"
        headers = {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json"
        }
        
        payload = {"url": url}
        try:
            response = requests.post(endpoint, json=payload, headers=headers)
            response.raise_for_status()
            
            data = response.json()
            if data.get("objects"):
                return data["objects"][0]
            else:
                raise BlinkAPIError("Failed to create short link: Invalid response")
                
        except requests.exceptions.RequestException as e:
            raise BlinkAPIError(f"Failed to create short link: {str(e)}")


def extract_urls(text: str) -> List[str]:
    """
    Extract URLs from text using regex, excluding tsdb.co URLs.
    
    Args:
        text: Text content to search for URLs
        domain_name: URLs to exclude
        
    Returns:
        List of URLs found in the text (excluding tsdb.co URLs)
    """
    # Regex pattern to match URLs
    url_pattern = r'https?://[^\s<>"{}|\\^`\[\]]+'
    urls = re.findall(url_pattern, text)

    # Clean up URLs - remove trailing parentheses that are part of markdown syntax
    # Remove trailing closing parenthesis if it's likely part of markdown
    # This handles cases like [link](https://example.com)
    urls = [url[:-1] if url.endswith(')') else url for url in urls]

    # Filter out URLs containing the exclude domains
    filtered_urls = []
    for domain_name in EXCLUDE_DOMAINS:
        filtered_urls.append([url for url in urls if domain_name not in url])

    # Get the intersection of the lists with the filtered urls
    intersection = set(filtered_urls[0])
    for it in range(1, len(filtered_urls)):
        intersection = list(intersection & set(filtered_urls[it]))
    
    return intersection


def main():
    """Main function to process text and create short links."""
    # Check for required environment variables
    email = os.getenv("BLINK_EMAIL")
    password = os.getenv("BLINK_PASSWORD")
    domain_name = os.getenv("BLINK_DOMAIN_NAME", "tsdb.co")
    api_base = os.getenv("BLINK_API_BASE", "https://app.bl.ink/api/v4")
    
    if not email:
        print("Error: BLINK_EMAIL environment variable not set", file=sys.stderr)
        sys.exit(1)
    if not password:
        print("Error: BLINK_PASSWORD environment variable not set", file=sys.stderr)
        sys.exit(1)

    # Get text input from command line argument
    if len(sys.argv) < 2:
        print("Usage: python shorturl.py <text>", file=sys.stderr)
        sys.exit(1)
    
    text = sys.argv[1]
    urls = extract_urls(text)

    if not urls:
        print("No URLs found in the provided text")
        print("\nOriginal text:")
        print(text)
        return
    
    print("=" * 80)
    print(f"Found {len(urls)} URL(s) to shorten:")
    for url in urls:
        print(f"  - {url}")
    print("=" * 80)
    
    # Initialize the shortener
    try:
        shortener = BlinkShortener(email=email, password=password, api_base=api_base)

        # get the domain ID
        domain_id = shortener.get_domain_id(domain_name)

        # Create a mapping of original URLs to short URLs
        url_mapping = {}
        
        # Create short links for each URL
        for url in urls:
            try:
                # Check if URL has a short link already and reuse it
                result = shortener.link_exists(url, domain_id)
                existing_url = True

                # URL does not exist, please create it
                if result is None:
                    result = shortener.create_short_link(url, domain_id)
                    existing_url = False

                short_link = result.get("short_link")
                url_mapping[url] = short_link
                if existing_url:
                    print(f"✓ Existing short url: {short_link} --> {url}")
                else:
                    print(f"✓ Created short url : {short_link} --> {url}")
            except BlinkAPIError as e:
                print(f"✗ Failed to shorten {url}: {str(e)}", file=sys.stderr)

        # Replace URLs in the original text
        modified_text = text
        for original_url, short_url in url_mapping.items():
            modified_text = modified_text.replace(original_url, short_url)
        
        # Output the modified text
        print("=" * 80)
        print(modified_text)
        print("=" * 80)

        with open("output.txt", "w") as f:
            f.write(modified_text)
        print("Output written to: output.txt")
        print("=" * 80)

    except BlinkAPIError as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()