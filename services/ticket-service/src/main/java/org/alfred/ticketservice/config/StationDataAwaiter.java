/**
 * Copyright (c) 2025 hcmurs. All rights reserved.
 *
 * Service: Ticket-Service
 *
 * This software is the confidential and proprietary information of hcmurs.
 * You shall not disclose such confidential information and shall use it only in
 * accordance with the terms of the license agreement you entered into with hcmurs.
 */
package org.alfred.ticketservice.config;

import java.time.Duration;
import lombok.extern.slf4j.Slf4j;
import org.alfred.ticketservice.client.StationClient;

/**
 * Blocks until station-service answers for a given station route, retrying with exponential
 * backoff. station-service seeds its data on ApplicationReadyEvent, so ticket-service can start
 * before that data exists.
 */
@Slf4j
public class StationDataAwaiter {

  private final StationClient stationClient;
  private final Duration timeout;
  private final Duration initialDelay;
  private final Duration maxDelay;

  public StationDataAwaiter(
      StationClient stationClient, Duration timeout, Duration initialDelay, Duration maxDelay) {
    this.stationClient = stationClient;
    this.timeout = timeout;
    this.initialDelay = initialDelay;
    this.maxDelay = maxDelay;
  }

  /**
   * Waits until station route {@code stationRouteId} is returned by station-service.
   *
   * @return the number of attempts it took
   * @throws IllegalStateException if the data is still missing after the timeout
   */
  public int await(long stationRouteId) {
    long deadline = System.nanoTime() + timeout.toNanos();
    long delayMs = Math.max(1, initialDelay.toMillis());
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        if (stationClient.getStationRouteById(stationRouteId).getData() != null) {
          return attempt;
        }
        log.info("Station route {} not seeded yet (attempt {})", stationRouteId, attempt);
      } catch (Exception e) {
        log.info(
            "station-service not ready (attempt {}): {}", attempt, e.getClass().getSimpleName());
      }
      if (System.nanoTime() + delayMs * 1_000_000L > deadline) {
        throw new IllegalStateException(
            "station-service did not return station route "
                + stationRouteId
                + " within "
                + timeout);
      }
      try {
        Thread.sleep(delayMs);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw new IllegalStateException("Interrupted while waiting for station-service", e);
      }
      delayMs = Math.min(delayMs * 2, maxDelay.toMillis());
    }
  }
}
