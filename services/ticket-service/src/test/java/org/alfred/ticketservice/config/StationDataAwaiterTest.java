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

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.alfred.ticketservice.client.StationClient;
import org.alfred.ticketservice.dto.station.StationRouteResponse;
import org.junit.jupiter.api.Test;

class StationDataAwaiterTest {

  /** Station client that fails, then returns empty data, then returns the route. */
  private static StationClient clientReadyAfter(int failures, int emptyResponses) {
    AtomicInteger calls = new AtomicInteger();
    return new StationClient() {
      @Override
      public ApiResponse<StationRouteResponse> getStationRouteById(Long id) {
        int call = calls.incrementAndGet();
        if (call <= failures) {
          throw new IllegalStateException("connection refused");
        }
        if (call <= failures + emptyResponses) {
          return ApiResponse.success(null, "not found");
        }
        return ApiResponse.success(StationRouteResponse.builder().id(id).build());
      }

      @Override
      public ApiResponse<List<StationRouteResponse>> getStationRoutesByRouteId(Long routeId) {
        throw new UnsupportedOperationException();
      }

      @Override
      public ApiResponse<Boolean> checkStationOnLine(Long start, Long end, Long station) {
        throw new UnsupportedOperationException();
      }
    };
  }

  private static StationDataAwaiter awaiter(StationClient client, Duration timeout) {
    return new StationDataAwaiter(client, timeout, Duration.ofMillis(1), Duration.ofMillis(4));
  }

  @Test
  void returnsOnFirstAttemptWhenStationIsReady() {
    assertEquals(1, awaiter(clientReadyAfter(0, 0), Duration.ofSeconds(5)).await(14L));
  }

  @Test
  void retriesThroughErrorsAndMissingDataUntilReady() {
    assertEquals(6, awaiter(clientReadyAfter(3, 2), Duration.ofSeconds(5)).await(14L));
  }

  @Test
  void failsAfterTimeoutWhenStationNeverBecomesReady() {
    StationClient neverReady = clientReadyAfter(Integer.MAX_VALUE, 0);
    assertThrows(
        IllegalStateException.class, () -> awaiter(neverReady, Duration.ofMillis(50)).await(14L));
  }
}
