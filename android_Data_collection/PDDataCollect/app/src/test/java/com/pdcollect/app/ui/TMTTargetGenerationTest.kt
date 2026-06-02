package com.pdcollect.app.ui

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.sqrt

class TMTTargetGenerationTest {

    @Test
    fun partA_hasExactly10Targets() {
        val targets = TrailMakingTestActivity.generatePartATargets()
        assertEquals(10, targets.size)
    }

    @Test
    fun partA_labelsAre1Through10() {
        val targets = TrailMakingTestActivity.generatePartATargets()
        for (i in 1..10) {
            assertEquals(i.toString(), targets[i - 1].label)
        }
    }

    @Test
    fun partA_indicesAre0Through9() {
        val targets = TrailMakingTestActivity.generatePartATargets()
        for (i in 0 until 10) {
            assertEquals(i, targets[i].index)
        }
    }

    @Test
    fun partB_hasExactly9Targets() {
        val targets = TrailMakingTestActivity.generatePartBTargets()
        assertEquals(9, targets.size)
    }

    @Test
    fun partB_correctAlternatingPattern() {
        val targets = TrailMakingTestActivity.generatePartBTargets()
        val expectedLabels = listOf("1", "A", "2", "B", "3", "C", "4", "D", "5")
        assertEquals(expectedLabels, targets.map { it.label })
    }

    @Test
    fun partB_indicesAreSequential() {
        val targets = TrailMakingTestActivity.generatePartBTargets()
        for (i in targets.indices) {
            assertEquals(i, targets[i].index)
        }
    }

    @Test
    fun layoutTargets_allWithinPaddedBounds() {
        val width = 1080
        val height = 1920
        val circleRadius = 35f
        val padding = circleRadius * 2.5f
        val bottomPadding = padding + 200f
        val targets = TrailMakingTestActivity.generatePartATargets()

        TrailMakingTestActivity.layoutTargets(targets, width, height, circleRadius)

        for (target in targets) {
            assertTrue(
                "Target ${target.label} x=${target.x} should be >= $padding",
                target.x >= padding
            )
            assertTrue(
                "Target ${target.label} x=${target.x} should be <= ${width - padding}",
                target.x <= width - padding
            )
            assertTrue(
                "Target ${target.label} y=${target.y} should be >= $padding",
                target.y >= padding
            )
            assertTrue(
                "Target ${target.label} y=${target.y} should be <= ${height - bottomPadding}",
                target.y <= height - bottomPadding
            )
        }
    }

    @Test
    fun layoutTargets_minimumDistanceBetweenTargets() {
        val width = 1080
        val height = 1920
        val circleRadius = 35f
        val minDistance = circleRadius * 4
        val targets = TrailMakingTestActivity.generatePartATargets()

        TrailMakingTestActivity.layoutTargets(targets, width, height, circleRadius)

        for (i in targets.indices) {
            for (j in i + 1 until targets.size) {
                val dx = targets[i].x - targets[j].x
                val dy = targets[i].y - targets[j].y
                val dist = sqrt(dx * dx + dy * dy)
                // Allow for the 200-attempt fallback case (very unlikely with 10 targets on 1080x1920)
                assertTrue(
                    "Targets ${targets[i].label} and ${targets[j].label} too close: $dist < $minDistance",
                    dist >= minDistance
                )
            }
        }
    }

    @Test
    fun layoutTargets_differentRandomProducesDifferentPositions() {
        val targets1 = TrailMakingTestActivity.generatePartATargets()
        val targets2 = TrailMakingTestActivity.generatePartATargets()

        TrailMakingTestActivity.layoutTargets(targets1, 1080, 1920, 35f, java.util.Random(1))
        TrailMakingTestActivity.layoutTargets(targets2, 1080, 1920, 35f, java.util.Random(2))

        val anyDifferent = targets1.zip(targets2).any { (t1, t2) ->
            t1.x != t2.x || t1.y != t2.y
        }
        assertTrue("Different random seeds should produce different layouts", anyDifferent)
    }
}
