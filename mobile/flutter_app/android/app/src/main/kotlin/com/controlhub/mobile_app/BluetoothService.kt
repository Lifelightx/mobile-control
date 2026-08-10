package com.controlhub.mobile_app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors
import android.util.Log

class BluetoothService(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private var bluetoothSocket: BluetoothSocket? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    // Common RFCOMM UUID
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPairedDevices" -> {
                if (bluetoothAdapter == null) {
                    result.error("NO_BLUETOOTH", "Bluetooth not supported", null)
                    return
                }
                val pairedDevices = bluetoothAdapter.bondedDevices
                val deviceList = pairedDevices?.map {
                    mapOf("name" to it.name, "address" to it.address)
                } ?: emptyList()
                result.success(deviceList)
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("INVALID_ARGUMENT", "Address is required", null)
                    return
                }
                connectToDevice(address, result)
            }
            "disconnect" -> {
                disconnect()
                result.success(null)
            }
            "send" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    sendData(data)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Data is required", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    private fun connectToDevice(address: String, result: MethodChannel.Result) {
        executor.execute {
            try {
                if (bluetoothAdapter == null) {
                    mainHandler.post { result.error("NO_BLUETOOTH", "Bluetooth not supported", null) }
                    return@execute
                }

                val device: BluetoothDevice = bluetoothAdapter.getRemoteDevice(address)
                
                // Always cancel discovery before connecting
                bluetoothAdapter.cancelDiscovery()

                bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                bluetoothSocket?.connect()
                
                inputStream = bluetoothSocket?.inputStream
                outputStream = bluetoothSocket?.outputStream

                mainHandler.post {
                    result.success(true)
                }
                
                startListening()

            } catch (e: Exception) {
                Log.e("BluetoothService", "Connection failed", e)
                disconnect()
                mainHandler.post {
                    result.error("CONNECTION_FAILED", e.message, null)
                }
            }
        }
    }

    private fun startListening() {
        val stream = inputStream ?: return
        val buffer = ByteArray(1024 * 16)
        
        executor.execute {
            while (bluetoothSocket?.isConnected == true) {
                try {
                    val bytesRead = stream.read(buffer)
                    if (bytesRead > 0) {
                        val readData = buffer.copyOfRange(0, bytesRead)
                        mainHandler.post {
                            eventSink?.success(readData)
                        }
                    }
                } catch (e: Exception) {
                    Log.e("BluetoothService", "Disconnected while listening", e)
                    disconnect()
                    mainHandler.post {
                        eventSink?.error("DISCONNECTED", "Connection lost", null)
                    }
                    break
                }
            }
        }
    }

    private fun sendData(data: ByteArray) {
        executor.execute {
            try {
                outputStream?.write(data)
                outputStream?.flush()
            } catch (e: Exception) {
                Log.e("BluetoothService", "Failed to send data", e)
                disconnect()
                mainHandler.post {
                    eventSink?.error("SEND_FAILED", e.message, null)
                }
            }
        }
    }

    private fun disconnect() {
        try {
            inputStream?.close()
            outputStream?.close()
            bluetoothSocket?.close()
        } catch (e: Exception) {
            Log.e("BluetoothService", "Error while disconnecting", e)
        } finally {
            inputStream = null
            outputStream = null
            bluetoothSocket = null
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }
}
